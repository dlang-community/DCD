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
		string[] args = [config.executable, "--config", workDir];
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
