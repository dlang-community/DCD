/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2014 Brian Schott
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module dcd.server.lsp.dfmt;

import std.algorithm;
import std.array;
import std.conv;
import std.experimental.logger;
import std.json;
import std.path;
import std.process : environment;

import dcd.server.lsp.handlers : uriToPath;

/**
 * External dfmt formatter for `textDocument/formatting`.
 *
 * Like D-Scanner, dfmt is deliberately NOT a dub dependency of DCD (both
 * vendor their own libdparse). The server shells out to a user-provided
 * `dfmt` executable: source goes in via stdin, formatted source comes back
 * on stdout. When no executable is found, formatting is simply unavailable
 * and the request returns null (no edits).
 *
 * Formatting runs synchronously on the request thread: unlike linting it is
 * user-initiated (Shift+Alt+F), so a short blocking call is expected — the
 * same way clangd blocks on its internal formatter. dfmt is fast (a few ms
 * for typical files).
 */
struct DfmtConfig
{
	/// Path to the dfmt executable. Empty = auto-detect on PATH.
	string executable;

	/// Whether formatting is enabled at all.
	bool enabled = true;

	/// Brace style used when no `.editorconfig` is discovered: one of
	/// "allman", "otbs", "stroustrup", "knr", or "default" (dfmt's own
	/// stock behavior, which is Allman). A project `.editorconfig` always
	/// wins over this. Set via `initializationOptions.dfmt.braceStyle`.
	string braceStyle = "default";

	/// Parses the formatter settings from `initializationOptions.dfmt`.
	static DfmtConfig fromOptions(JSONValue options)
	{
		DfmtConfig config;
		if (options.type != JSONType.object)
			return config;
		if ("enabled" in options && options["enabled"].type == JSONType.true_)
			config.enabled = true;
		else if ("enabled" in options && options["enabled"].type == JSONType.false_)
			config.enabled = false;
		if ("executable" in options && options["executable"].type == JSONType.string)
			config.executable = options["executable"].str;
		if ("braceStyle" in options && options["braceStyle"].type == JSONType.string)
		{
			immutable style = options["braceStyle"].str;
			if (style.among!("allman", "otbs", "stroustrup", "knr", "default"))
				config.braceStyle = style;
		}
		return config;
	}
}

/**
 * Formats source code with the external dfmt tool.
 *
 * Params:
 *     config = the formatter configuration (executable path)
 *     uri = the document URI; its directory is passed to dfmt via
 *         `--config` so a project `.editorconfig` is honored
 *     source = the current document text
 * Returns:
 *     the formatted text, or `null` if formatting is unavailable (dfmt
 *     not found) or failed (syntax errors in the document)
 */
string formatWithDfmt(ref DfmtConfig config, string uri, string source)
{
	if (!config.enabled)
		return null;
	if (!resolveExecutable(config))
		return null;

	import std.process : pipeProcess, Redirect, Config, wait;

	string output;
	try
	{
		// Pass the document's directory so dfmt picks up the project's
		// .editorconfig (indent style/size, brace style, ...).
		string workDir = uriToPath(uri).dirName;
		string configDir = workDir;
		if (config.braceStyle != "default" && !editorconfigDiscovered(workDir))
		{
			// No .editorconfig anywhere: pass a generated default that
			// pins the configured brace style (see DfmtConfig.braceStyle).
			// A discovered project .editorconfig always wins.
			string generated = defaultEditorconfig(config.braceStyle);
			if (generated.length)
				configDir = generated;
		}
		string[] args = [config.executable, "--config", configDir];
		auto pipes = pipeProcess(args,
			Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout,
			null, Config.none, workDir);
		pipes.stdin.rawWrite(source);
		pipes.stdin.close();
		auto app = appender!(char[])();
		foreach (chunk; pipes.stdout.byChunk(4096))
			app.put(chunk);
		auto status = wait(pipes.pid);
		output = app.data.idup;
		// dfmt exits 0 even on syntax errors, printing `[error]:` lines
		// into the output before the (mangled) formatted text. Detect
		// those and refuse to format: applying the output would corrupt
		// the user's document.
		if (status != 0 || output.canFind("[error]:"))
		{
			immutable preview = output.length > 200
				? output[0 .. 200] ~ "..." : output;
			warningf("dfmt: failed to format %s (exit %s): %s",
				uri, status, preview);
			return null;
		}
	}
	catch (Exception e)
	{
		warningf("dfmt: failed to run: %s", e.msg);
		return null;
	}
	return output;
}

/**
 * Resolves the dfmt executable: a bare name (no directory component) is
 * looked up on the PATH, a path with a directory component must exist.
 * The resolved path is cached in `config.executable`.
 */
private bool resolveExecutable(ref DfmtConfig config)
{
	import std.file : exists;

	string name = config.executable.length ? config.executable : "dfmt";
	if (name.dirName == ".")
	{
		auto pathEnv = environment.get("PATH", "");
		foreach (dir; pathEnv.splitter(':'))
		{
			if (dir.empty)
				continue;
			auto candidate = buildPath(dir, name);
			if (exists(candidate))
			{
				config.executable = candidate;
				return true;
			}
		}
		// Not an error: formatting is an optional add-on.
		info("dfmt: not found on PATH, formatting unavailable "
			~ "(install dfmt or set the executable path to enable)");
		return false;
	}
	if (exists(config.executable))
		return true;
	warningf("dfmt: configured executable '%s' does not exist, "
		~ "formatting unavailable", config.executable);
	return false;
}

/**
 * Whether an `.editorconfig` would be discovered for the given directory:
 * dfmt (via editorconfig-d) searches the directory itself and every
 * ancestor for a file with exactly that name.
 */
private bool editorconfigDiscovered(string workDir)
{
	import std.file : exists;

	for (string dir = workDir; ; dir = dir.dirName)
	{
		if (exists(buildPath(dir, ".editorconfig")))
			return true;
		// dirName("/") == "/": stop once the path stops shrinking.
		if (dir == dir.dirName)
			break;
	}
	return false;
}

/**
 * Writes a minimal `.editorconfig` that pins the given brace style into a
 * per-server temp directory and returns the DIRECTORY path (dfmt's
 * `--config` takes a directory, not a file). The file is shared by all
 * format requests of this server process; it is never cleaned up (a few
 * bytes in the temp dir). Returns an empty string when it cannot be
 * written — formatting then just uses dfmt's stock defaults.
 */
private string defaultEditorconfig(string braceStyle)
{
	import std.file : mkdirRecurse, tempDir, write;

	static string cachedPath;
	static string cachedStyle;
	if (cachedPath.length && cachedStyle == braceStyle)
		return cachedPath;

	try
	{
		auto dir = buildPath(tempDir, "dcd-lsp");
		mkdirRecurse(dir);
		write(buildPath(dir, ".editorconfig"),
			"root = true\n\n[*.d]\ndfmt_brace_style = " ~ braceStyle ~ "\n");
		cachedPath = dir;
		cachedStyle = braceStyle;
	}
	catch (Exception e)
	{
		warningf("dfmt: could not write default editorconfig: %s", e.msg);
		cachedPath = "";
	}
	return cachedPath;
}

version (unittest)
{
	unittest
	{
		// Bare name and empty name both mean PATH lookup; a path with a
		// directory component is taken literally.
		DfmtConfig c;
		assert(DfmtConfig.fromOptions(parseJSON(`{}`)).enabled);
		assert(!DfmtConfig.fromOptions(parseJSON(`{"enabled": false}`)).enabled);
		assert(DfmtConfig.fromOptions(
			parseJSON(`{"executable": "/usr/local/bin/dfmt"}`)).executable
			== "/usr/local/bin/dfmt");
	}
}
