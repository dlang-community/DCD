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

module dcd.server.lsp.dscanner;

import core.sync.condition : Condition;
import core.sync.mutex : Mutex;
import core.thread : Thread;
import core.time : MonoTime, msecs, Duration;

import std.algorithm;
import std.array;
import std.conv;
import std.experimental.logger;
import std.json;
import std.path : buildPath, dirName;
import std.string;

import dcd.server.lsp.document;
import dcd.server.lsp.jsonrpc;
import dcd.server.lsp.protocol;

/**
 * Configuration for the external D-Scanner linter.
 *
 * D-Scanner is deliberately NOT a dub dependency of DCD: both projects
 * vendor their own copies of libdparse/dsymbol and linking them together
 * would create symbol conflicts. Instead the LSP server shells out to a
 * user-provided `dscanner` executable, exactly like clangd shells out to
 * external formatters. When no executable is configured or found, the
 * linter is simply inactive.
 */
struct DScannerConfig
{
	/// Path to the dscanner executable. Empty = auto-detect on PATH.
	string executable;

	/// Whether linting is enabled at all.
	bool enabled = true;

	/// Minimum pause between lint runs (debounce for continuous typing).
	Duration debounce = 500.msecs;

	/// Extra command line arguments passed to dscanner (e.g. a custom
	/// `--config` file).
	string[] extraArgs;

	/// Path to an explicit dscanner.ini configuration file. Empty = let
	/// dscanner discover one (it searches upward from the working
	/// directory, which the linter sets to the document's directory, so a
	/// `dscanner.ini` at the project root just works).
	string configFile;

	/// Disable the undocumented-declaration check when no dscanner.ini is
	/// discovered. D-Scanner enables it by default, which floods real
	/// projects with "Public declaration 'x' is undocumented" noise; most
	/// users want it off unless they opted in via a config file.
	bool disableUndocumentedByDefault = true;

	/// Parses the linter settings from `initializationOptions.dscanner`.
	static DScannerConfig fromOptions(JSONValue options)
	{
		DScannerConfig config;
		if (options.type != JSONType.object)
			return config;
		if ("enabled" in options && options["enabled"].type == JSONType.true_)
			config.enabled = true;
		else if ("enabled" in options && options["enabled"].type == JSONType.false_)
			config.enabled = false;
		if ("executable" in options && options["executable"].type == JSONType.string)
			config.executable = options["executable"].str;
		if ("configFile" in options && options["configFile"].type == JSONType.string)
			config.configFile = options["configFile"].str;
		if ("disableUndocumentedByDefault" in options
			&& options["disableUndocumentedByDefault"].type == JSONType.false_)
			config.disableUndocumentedByDefault = false;
		if ("debounceMs" in options && options["debounceMs"].type == JSONType.integer)
		{
			auto ms = options["debounceMs"].integer;
			if (ms > 0 && ms < 60_000)
				config.debounce = ms.msecs;
		}
		if ("arguments" in options && options["arguments"].type == JSONType.array)
		{
			foreach (arg; options["arguments"].array)
				if (arg.type == JSONType.string)
					config.extraArgs ~= arg.str;
		}
		return config;
	}
}

/**
 * A snapshot of a document handed to the linter thread.
 */
private struct LintJob
{
	string uri;
	string text;
	long docVersion;
}

/**
 * Runs D-Scanner as an external process and publishes its findings as LSP
 * diagnostics.
 *
 * Performance model (the request thread must never stall):
 *
 * - `submit` only takes a mutex and appends to an array; it never spawns
 *   a process and never parses anything. didOpen/didChange cost is a few
 *   microseconds regardless of dscanner's speed.
 * - A single background worker thread consumes the queue. Only the
 *   LATEST snapshot per document is ever linted: intermediate states
 *   produced by fast typing coalesce into one run.
 * - A debounce interval enforces a minimum pause between runs, so
 *   continuous typing can never saturate a core with dscanner processes.
 * - The worker is a daemon thread and exits when `stop` is called, so it
 *   never keeps the server alive on its own.
 */
final class DScannerLinter
{
private:
	DScannerConfig config;
	string[] baseArgs;
	Mutex mutex;
	Condition condition;
	bool stopped;
	LintJob[] queue;
	Thread worker;

public:
	/**
	 * Creates a linter. The worker thread is only started when the
	 * executable actually resolves; otherwise `active` is false and every
	 * other method is a no-op.
	 */
	this(DScannerConfig config)
	{
		this.config = config;
		if (!config.enabled)
			return;
		if (!resolveExecutable())
			return;
		baseArgs = [config.executable, "--report", "stdin"] ~ config.extraArgs;
		mutex = new Mutex;
		condition = new Condition(mutex);
		worker = new Thread(&workerLoop);
		worker.isDaemon = true;
		worker.start();
	}

	/// True when the linter is running (executable found and enabled).
	bool active() const @property
	{
		return worker !is null;
	}

	/**
	 * Queues a document snapshot for linting. Cheap: one mutex lock and an
	 * array append. Safe to call from the request thread on every
	 * didOpen/didChange.
	 */
	void submit(string uri, string text, long docVersion)
	{
		if (!active)
			return;
		debug (dscanner_lint)
			infof("dscanner: queueing lint for %s (version %s)",
				uri, docVersion);
		synchronized (mutex)
		{
			// Coalesce: replace a queued snapshot of the same document so
			// only the newest version is ever linted.
			foreach (ref job; queue)
			{
				if (job.uri == uri)
				{
					job.text = text;
					job.docVersion = docVersion;
					condition.notifyAll();
					return;
				}
			}
			queue ~= LintJob(uri, text, docVersion);
			condition.notifyAll();
		}
	}

	/// Drops all queued snapshots for a closed document.
	void forget(string uri)
	{
		if (!active)
			return;
		synchronized (mutex)
			queue = queue.filter!(j => j.uri != uri).array;
	}

	/**
	 * Stops the worker and waits for it to finish. The in-flight dscanner
	 * run (if any) is abandoned; its result is discarded.
	 */
	void stop()
	{
		if (!active)
			return;
		synchronized (mutex)
		{
			stopped = true;
			condition.notifyAll();
		}
		worker.join();
		worker = null;
	}

private:
	/**
	 * Resolves the dscanner executable: an explicitly configured path is
	 * used as-is (must exist), otherwise "dscanner" is looked up on the
	 * PATH.
	 */
	bool resolveExecutable()
	{
		import std.file : exists;
		import std.path : buildPath, dirName;
		import std.process : environment;

		// Resolve the configured executable. A bare name (no directory
		// component, like the default "dscanner") means "look it up on
		// the PATH" — the same convention as dcd.serverPath. A path with
		// a directory component must exist as given.
		string name = config.executable;
		if (name.empty || name.dirName == ".")
		{
			if (!name.length)
				name = "dscanner";
			// PATH lookup: try each PATH entry for <entry>/<name>
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
			// Not an error: linting is an optional add-on.
			infof("dscanner: '%s' not found on PATH, linting disabled "
				~ "(install D-Scanner or set the executable path to enable)",
				name);
			return false;
		}
		if (exists(config.executable))
			return true;
		warningf("dscanner: configured executable '%s' does not exist, "
			~ "linting disabled", config.executable);
		return false;
	}

	/**
	 * The background loop: wait for work, debounce, lint the newest
	 * snapshot of each document, publish diagnostics.
	 */
	void workerLoop()
	{
		// Ignore SIGPIPE in this thread: if the client goes away while we
		// write a notification, the default action (kill the process)
		// would take the whole server down. The main read loop notices
		// EOF on stdin and exits cleanly.
		version (Posix)
		{
			import core.stdc.signal : signal, SIG_IGN;
			import core.sys.posix.signal : SIGPIPE;
			signal(SIGPIPE, SIG_IGN);
		}

		MonoTime lastRun;
		bool haveLastRun;
		while (true)
		{
			LintJob job;
			synchronized (mutex)
			{
				while (queue.empty && !stopped)
					condition.wait();
				if (stopped)
					return;
				// Take the oldest queued job; newer snapshots of the same
				// document have replaced it in place (coalescing).
				job = queue[0];
				queue = queue[1 .. $];
			}

			// Debounce: enforce a minimum pause between dscanner runs so
			// continuous typing cannot spawn processes back to back.
			if (haveLastRun)
			{
				auto elapsed = MonoTime.currTime - lastRun;
				if (elapsed < config.debounce)
				{
					auto remaining = config.debounce - elapsed;
					// Sleep, but wake up early if stopped.
					synchronized (mutex)
					{
						if (stopped)
							return;
						condition.wait(remaining);
						if (stopped)
							return;
					}
					// After the wait, re-check for a newer snapshot of
					// this document and use it instead.
					synchronized (mutex)
					{
						foreach (ref queued; queue)
							if (queued.uri == job.uri)
							{
								job = queued;
								queue = queue.filter!(j => j.uri != job.uri).array;
								break;
							}
					}
				}
			}
			lastRun = MonoTime.currTime;
			haveLastRun = true;

			debug (dscanner_lint)
				infof("dscanner: linting %s (version %s, %s bytes)",
					job.uri, job.docVersion, job.text.length);

			lint(job);
		}
	}

	/**
	 * Runs dscanner on one snapshot and publishes the diagnostics.
	 */
	private void lint(LintJob job)
	{
		import std.process : pipeProcess, Redirect, Config, wait;

		auto started = MonoTime.currTime;
		string output;
		try
		{
			// Run dscanner with the document's directory as working
			// directory so it discovers a dscanner.ini at the project root
			// (it searches upward from the cwd). An explicitly configured
			// ini file is passed via --config and wins over discovery.
			string[] args = baseArgs;
			string workDir;
			{
				import dcd.server.lsp.handlers : uriToPath;
				import std.path : dirName;
				workDir = uriToPath(job.uri).dirName;
			}
			if (config.configFile.length)
				args ~= ["--config", config.configFile];
			else if (config.disableUndocumentedByDefault
				&& !dscannerIniDiscovered(workDir))
			{
				// No user config anywhere: fall back to a generated ini
				// that disables the undocumented-declaration check (see
				// DScannerConfig.disableUndocumentedByDefault).
				string generated = defaultDscannerIni();
				if (generated.length)
					args ~= ["--config", generated];
			}
			auto pipes = pipeProcess(args,
				Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout,
				null, Config.none, workDir);
			pipes.stdin.rawWrite(job.text);
			pipes.stdin.close();
			// Read all output; stderr is merged into stdout so parse
			// errors of the report itself surface in the log.
			auto app = appender!(char[])();
			foreach (chunk; pipes.stdout.byChunk(4096))
				app.put(chunk);
			wait(pipes.pid);
			output = app.data.idup;
		}
		catch (Exception e)
		{
			warningf("dscanner: failed to run: %s", e.msg);
			return;
		}

		Diagnostic[] diagnostics;
		try
			diagnostics = parseReport(output, job.text);
		catch (Exception e)
		{
			// Include the beginning of the raw output: when dscanner
			// itself fails (e.g. missing $HOME, bad config), its crash
			// message is the output and "Unexpected character" alone
			// hides the actual cause.
			immutable preview = output.length > 200
				? output[0 .. 200] ~ "..." : output;
			warningf("dscanner: failed to parse report for %s: %s\n"
				~ "dscanner output was: %s",
				job.uri, e.msg, preview);
			return;
		}

		// Build the publishDiagnostics notification. Versioned
		// diagnostics let the client drop stale results.
		JSONValue params = parseJSON(`{}`);
		params["uri"] = JSONValue(job.uri);
		if (diagnostics.length)
			params["diagnostics"] = diagnosticsToJson(diagnostics);
		else
			params["diagnostics"] = JSONValue((JSONValue[]).init);
		JSONValue notification = makeNotification(
			"textDocument/publishDiagnostics", params);
		writeMessageRaw(notification.toString());

		auto elapsed = MonoTime.currTime - started;
		infof("dscanner: linted %s in %s ms (%s diagnostics)",
			job.uri, elapsed.total!"msecs", diagnostics.length);
	}

	/**
	 * Parses the JSON report emitted by `dscanner --report` into LSP
	 * diagnostics.
	 *
	 * The report's `index`/`endIndex` are byte offsets into the source,
	 * which is exactly what DCD's position converter wants; `line` and
	 * `column` are 1-based and are only used as a fallback when the byte
	 * offsets are missing or out of bounds.
	 */
	static Diagnostic[] parseReport(string report, string source)
	{
		auto parsed = parseJSON(report);
		enforceReport(parsed);
		Diagnostic[] diagnostics;
		auto issues = parsed["issues"].array;
		foreach (issue; issues)
		{
			if ("index" !in issue || "endIndex" !in issue)
				continue;
			Diagnostic diag;
			diag.message = issue["message"].str;
			diag.severity = severityOf(issue["type"].str);
			diag.range = rangeFor(issue, source);
			if (diag.range.start.line == diag.range.end.line
				&& diag.range.start.character == diag.range.end.character
				&& diag.range.end.line == 0 && diag.range.end.character == 0)
				continue; // unresolvable position, skip
			diagnostics ~= diag;
		}
		return diagnostics;
	}

private:
	/// Validates that the JSON looks like a dscanner report.
	static void enforceReport(JSONValue parsed)
	{
		import std.exception : enforce;
		enforce(parsed.type == JSONType.object, "report is not a JSON object");
		enforce("issues" in parsed, "report has no 'issues' member");
		enforce(parsed["issues"].type == JSONType.array,
			"report 'issues' is not an array");
	}

	/// Maps a dscanner issue type to an LSP diagnostic severity.
	static int severityOf(string type)
	{
		switch (type)
		{
		case "error":
			return 1; // Error
		case "warn":
			return 2; // Warning
		case "hint":
			return 4; // Hint
		default:
			return 3; // Information
		}
	}

	/**
	 * Converts an issue's location to an LSP range.
	 *
	 * Byte offsets are authoritative (they come from the same lexer D
	 * tooling uses); the 1-based line/column is the fallback for issues
	 * without usable offsets (e.g. syntax errors reported by the parser
	 * callback, which pass [0, 0] ranges).
	 */
	static Range rangeFor(JSONValue issue, string source)
	{
		immutable size_t index = issue["index"].integer.to!size_t;
		immutable size_t endIndex = issue["endIndex"].integer.to!size_t;

		// Build a throwaway document to reuse the line index + UTF-16
		// conversion logic. This is cheap (one scan of the source).
		TextDocument doc;
		doc.text = source;
		doc.reindex();

		// dscanner's syntax-error messages carry no usable byte range
		// (the parser callback reports [0, 0]); fall back to line/column.
		immutable bool usableOffsets = index != endIndex
			|| (index > 0 && endIndex > 0);
		if (usableOffsets && index < source.length
			&& endIndex <= source.length && endIndex >= index)
		{
			auto start = PositionConverter(PositionEncoding.utf16)
				.toPosition(doc, index);
			auto end = PositionConverter(PositionEncoding.utf16)
				.toPosition(doc, endIndex);
			return Range(start, end);
		}

		// Fallback: 1-based line/column.
		immutable size_t line = issue["line"].integer.to!size_t;
		immutable size_t column = issue["column"].integer.to!size_t;
		if (line == 0 || line > doc.lineStarts.length)
			return Range(Position(0, 0), Position(0, 0));
		// Convert 1-based column to a byte offset within the line.
		size_t lineStart = doc.lineStarts[line - 1];
		size_t lineEnd = line < doc.lineStarts.length
			? doc.lineStarts[line] : source.length;
		size_t byteInLine = column > 0 ? column - 1 : 0;
		// Clamp to the line length.
		if (lineStart + byteInLine > lineEnd)
			byteInLine = lineEnd - lineStart;
		auto pos = PositionConverter(PositionEncoding.utf16)
			.toPosition(doc, lineStart + byteInLine);
		return Range(pos, pos);
	}

	/// Serializes diagnostics for publishDiagnostics.
	static JSONValue diagnosticsToJson(Diagnostic[] diagnostics)
	{
		JSONValue[] items;
		foreach (diag; diagnostics)
			items ~= diag.toJson();
		return JSONValue(items);
	}
}

/**
 * Runs dscanner on a source text and returns the diagnostics, for testing.
 */
Diagnostic[] lintTextForTest(string report, string source)
{
	return DScannerLinter.parseReport(report, source);
}

/**
 * Whether dscanner would discover a `dscanner.ini` for the given working
 * directory: it searches the directory itself and every ancestor for a file
 * with exactly that name (mirrors dscanner's tryFindConfigurationLocation).
 */
private bool dscannerIniDiscovered(string workDir)
{
	import std.file : exists;

	for (string dir = workDir; ; dir = dir.dirName)
	{
		if (exists(buildPath(dir, "dscanner.ini")))
			return true;
		// dirName("/") == "/": stop once the path stops shrinking.
		if (dir == dir.dirName)
			break;
	}
	return false;
}

/**
 * Writes a minimal dscanner.ini that disables only the
 * undocumented-declaration check into a per-server temp directory and
 * returns its path. The file is shared by all lint runs of this server
 * process; it is never cleaned up (a few bytes in the temp dir, like
 * clangd's crash reports). Returns an empty string when it cannot be
 * written (e.g. no temp dir) — the linter then just runs dscanner with
 * its stock defaults.
 */
private string defaultDscannerIni()
{
	import std.file : exists, mkdirRecurse, tempDir, write;

	static string cachedPath;
	static bool attempted;
	if (attempted)
		return cachedPath;
	attempted = true;

	try
	{
		auto dir = buildPath(tempDir, "dcd-lsp");
		mkdirRecurse(dir);
		auto ini = buildPath(dir, "dscanner.ini");
		if (!exists(ini))
			write(ini, "[analysis.config.StaticAnalysisConfig]\n"
				~ "undocumented_declaration_check=\"disabled\"\n");
		cachedPath = ini;
	}
	catch (Exception e)
	{
		warningf("dscanner: could not write default ini: %s", e.msg);
		cachedPath = "";
	}
	return cachedPath;
}

version (unittest)
{
	unittest
	{
		// A minimal report in the shape dscanner emits.
		auto report = `
		{
			"issues": [
				{
					"key": "dscanner.suspicious.unmodified",
					"fileName": "stdin",
					"line": 3, "column": 6,
					"endLine": 3, "endColumn": 7,
					"index": 31, "endIndex": 32,
					"message": "Variable a is never modified.",
					"type": "warn"
				}
			]
		}`;
		auto source = "module test;\nvoid foo() {\n\tint a = 1;\n}\n";
		auto diags = lintTextForTest(report, source);
		assert(diags.length == 1);
		assert(diags[0].severity == 2);
		assert(diags[0].range.start.line == 2);
		assert(diags[0].range.start.character == 5);
		assert(diags[0].range.end.character == 6);
		assert(diags[0].message == "Variable a is never modified.");
	}

	unittest
	{
		// Byte offsets out of bounds -> fallback to line/column.
		auto report = `
		{
			"issues": [
				{
					"key": "dscanner.syntax",
					"fileName": "stdin",
					"line": 2, "column": 6,
					"endLine": 2, "endColumn": 6,
					"index": 0, "endIndex": 0,
					"message": "Syntax error.",
					"type": "error"
				}
			]
		}`;
		auto source = "module test;\nvoid foo() {\n";
		auto diags = lintTextForTest(report, source);
		assert(diags.length == 1);
		assert(diags[0].severity == 1);
		assert(diags[0].range.start.line == 1);
		assert(diags[0].range.start.character == 5);
	}

	unittest
	{
		// Empty issues list.
		auto report = `{"issues": []}`;
		auto diags = lintTextForTest(report, "module test;\n");
		assert(diags.length == 0);
	}
}
