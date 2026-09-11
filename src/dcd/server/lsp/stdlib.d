/**
 * Auto-detection of the local D standard library (Phobos + druntime)
 * import directories.
 *
 * The primary source is the compiler's own configuration file - the same
 * file the compiler itself consults to find its stdlib, so any install
 * location works:
 *
 * $(UL
 *     $(LI LDC: `ldc2.conf` - `default` section, `switches` /
 *         `post-switches` arrays, `-I` entries, `%%ldcbinarypath%%`
 *         substitution)
 *     $(LI DMD: `dmd.conf` - `[Environment64]`/`[Environment32]` sections,
 *         `DFLAGS=` line, `-I` entries, `%@P%` substitution for the conf
 *         file's directory))
 *
 * The compiler binary is located via `PATH` (or an explicit path), and the
 * config file is searched next to the binary and in the system-wide
 * locations the compilers document. Hardcoded well-known install
 * directories are only used as a last-resort fallback.
 *
 */
module dcd.server.lsp.stdlib;

import std.algorithm;
import std.array;
import std.ascii : isWhite;
import std.experimental.logger;
import std.file;
import std.path;
import std.process : environment;
import std.stdio : File;
import std.string;
import std.uni : sicmp;

/**
 * Returns the import directories of the local Phobos/druntime
 * installation, or an empty array when none was found.
 *
 * Params:
 *     compilerPath = optional explicit compiler path (e.g. from a
 *         client setting); when empty, `dmd`, `ldc2`, and `ldc` are
 *         looked up on the `PATH`.
 */
string[] detectStdlibImportPaths(string compilerPath = null)
{
	string[] result;
	if (detectFromCompilerConfig(compilerPath, result))
		return result;

	trace("stdlib: no compiler config found, trying hardcoded paths");
	if (detectFromWellKnownPaths(result))
		return result;

	warning("stdlib: could not locate the D standard library; "
		~ "`import std.*` will not resolve. Pass the import path "
		~ "explicitly via -I or dcd.conf.");
	return [];
}

// ---------------------------------------------------------------------------
// Compiler lookup
// ---------------------------------------------------------------------------

/**
 * Finds an executable on the `PATH` and returns its absolute path, or
 * `null` when not found.
 */
private string searchPathFor(string executable)
{
	version (Posix)
	{
		enum string exeExt = "";
		enum char separator = ':';
	}
	else
	{
		enum string exeExt = ".exe";
		enum char separator = ';';
	}

	auto pathEnv = environment.get("PATH", "");
	foreach (dir; pathEnv.splitter(separator))
	{
		if (dir.empty)
			continue;
		auto candidate = buildPath(dir, executable ~ exeExt);
		if (exists(candidate) && isFile(candidate))
			return buildNormalizedPath(candidate);
	}
	return null;
}

version (Windows)
{
	private enum dmdConfName = "sc.ini";
	private enum ldcConfName = "ldc2.conf";
	private enum dmdExeName = "dmd.exe";
	private enum ldcExeName = "ldc2.exe";
	private enum ldcExeAltName = "ldc.exe";
}
else
{
	private enum dmdConfName = "dmd.conf";
	private enum ldcConfName = "ldc2.conf";
	private enum dmdExeName = "dmd";
	private enum ldcExeName = "ldc2";
	private enum ldcExeAltName = "ldc";
}

/**
 * Resolves the compiler binary: an absolute/relative explicit path is
 * used as given (when it exists), otherwise the executable is looked up
 * on the `PATH`.
 */
private string resolveCompiler(string compilerPath)
{
	if (!compilerPath.empty)
	{
		if (compilerPath.canFind(dirSeparator))
		{
			if (exists(compilerPath) && isFile(compilerPath))
				return buildNormalizedPath(compilerPath);
			warningf("stdlib: configured compiler '%s' does not exist",
				compilerPath);
			return null;
		}
		// A bare name: fall through to the PATH lookup below.
	}

	// Prefer the compiler dub would use, mirroring serve-d's
	// d.dubCompiler default.
	foreach (name; [dmdExeName, ldcExeName, ldcExeAltName])
	{
		auto found = searchPathFor(name);
		if (!found.empty)
			return found;
	}
	return null;
}

// ---------------------------------------------------------------------------
// Config file discovery
// ---------------------------------------------------------------------------

/**
 * Locates the compiler's config file and extracts the stdlib import
 * paths from it.
 */
private bool detectFromCompilerConfig(string compilerPath, ref string[] result)
{
	auto compiler = resolveCompiler(compilerPath);
	if (compiler.empty)
	{
		trace("stdlib: no D compiler found on PATH");
		return false;
	}

	auto binDir = compiler.dirName;
	auto binName = compiler.baseName.stripExtension;

	// Config file candidates, in the order the compilers document them
	// (LDC: driver/configfile.cpp, DMD: dmd -v/conf docs).
	string[] confCandidates;
	if (sicmp(binName, "ldc2") == 0 || sicmp(binName, "ldc") == 0)
	{
		confCandidates ~= ldcConfCandidates(binDir);
	}
	else if (sicmp(binName, "dmd") == 0)
	{
		confCandidates ~= dmdConfCandidates(binDir);
	}
	else
	{
		// Unknown compiler name: try both config formats.
		confCandidates ~= ldcConfCandidates(binDir);
		confCandidates ~= dmdConfCandidates(binDir);
	}

	foreach (conf; confCandidates)
	{
		if (!exists(conf))
			continue;
		// LDC >= 1.42 generates the config as a DIRECTORY of numbered
		// .conf files (etc/ldc2.conf/50-target-default.conf, ...); the
		// compiler itself reads every file in it (iterateConfigFiles),
		// sorted numerically, later files overriding earlier ones.
		if (isDir(conf))
		{
			string[] files = dirEntries(conf, SpanMode.shallow)
				.filter!(a => a.isFile && a.name.endsWith(".conf"))
				.map!(a => a.name).array;
			sort(files);
			foreach (f; files)
			{
				string[] paths;
				if (parseLdcConf(f, binDir, paths) && !paths.empty)
				{
					result = paths.filter!(a => !a.empty && exists(a)).array;
					if (!result.empty)
					{
						tracef("stdlib: found via %s: %s", f, result);
						return true;
					}
				}
			}
			continue;
		}
		if (!isFile(conf))
			continue;
		string[] paths;
		if (parseLdcConf(conf, binDir, paths) || parseDmdConf(conf, paths))
		{
			if (!paths.empty)
			{
				result = paths.filter!(a => !a.empty && exists(a)).array;
				if (!result.empty)
				{
					tracef("stdlib: found via %s: %s", conf, result);
					return true;
				}
			}
		}
	}
	return false;
}

/**
 * LDC config file locations, mirroring LDC's own search order.
 */
private string[] ldcConfCandidates(string binDir)
{
	string[] candidates;
	// Next to the binary (covers Homebrew: /opt/homebrew/etc is a symlink
	// to the Cellar, and bin/../etc/ldc2.conf resolves through it).
	candidates ~= buildPath(binDir, "..", "etc", ldcConfName);
	// System-wide locations.
	candidates ~= buildPath("/etc", ldcConfName);
	candidates ~= buildPath("/etc/ldc", ldcConfName);
	candidates ~= buildPath("/usr/local/etc", ldcConfName);
	candidates ~= buildPath("/usr/local/etc/ldc", ldcConfName);
	// User-level.
	auto home = environment.get("HOME", "");
	if (!home.empty)
	{
		candidates ~= buildPath(home, ".ldc", ldcConfName);
		version (Windows)
			candidates ~= buildPath(home, ldcConfName);
	}
	return candidates;
}

/**
 * DMD config file locations, mirroring DMD's own search order.
 */
private string[] dmdConfCandidates(string binDir)
{
	string[] candidates;
	// Next to the binary (dlang.org installers: <prefix>/dmd2/linux/bin64/
	// dmd.conf sits next to the binary).
	candidates ~= buildPath(binDir, dmdConfName);
	// System-wide.
	candidates ~= buildPath("/etc", dmdConfName);
	candidates ~= buildPath("/usr/local/etc", dmdConfName);
	// User-level.
	auto home = environment.get("HOME", "");
	if (!home.empty)
		candidates ~= buildPath(home, dmdConfName);
	return candidates;
}

// ---------------------------------------------------------------------------
// LDC config parsing
// ---------------------------------------------------------------------------

/**
 * Parses an `ldc2.conf` file: the `default:` section's `switches` and
 * `post-switches` arrays, extracting `-I` entries and substituting
 * `%%ldcbinarypath%%` with the compiler's bin directory.
 *
 * The grammar is simple enough for a line-based scanner: section headers
 * are `name:` or `"regex":`, arrays are `key = [ "a", "b" ];`, entries
 * are quoted strings possibly followed by `//` comments.
 */
private bool parseLdcConf(string confPath, string binDir, ref string[] paths)
{
	string[] switches;
	auto collect = (string[] entries)
	{
		foreach (entry; entries)
		{
			auto sw = entry
				.replace("%%ldcbinarypath%%", binDir)
				.replace("%ldcbinarypath%", binDir);
			if (sw.startsWith("-I") && sw.length > 2)
				switches ~= sw[2 .. $];
		}
	};

	bool inDefaultSection;
	bool collecting;

	foreach (line; File(confPath).byLineCopy)
	{
		auto trimmed = line.strip;
		if (trimmed.empty || trimmed.startsWith("//"))
			continue;

		// Section header: `default:` or `"regex":` - always ends with
		// `:`, unlike array entries (`"-I..."`), which also start with
		// a quote.
		if (trimmed.endsWith(":")
			&& (trimmed.startsWith("default:") || trimmed.startsWith("\"")))
		{
			inDefaultSection = trimmed.startsWith("default:");
			collecting = false;
			continue;
		}

		if (!inDefaultSection)
			continue;

		// Array start: `switches = [`
		if (trimmed.startsWith("switches") || trimmed.startsWith("post-switches"))
		{
			collecting = true;
			// Handle `switches = [ "..." ];` on a single line.
			auto eq = trimmed.indexOf('=');
			if (eq != -1)
			{
				auto rest = trimmed[eq + 1 .. $];
				collect(parseQuotedEntries(rest));
				if (rest.canFind(']'))
					collecting = false;
			}
			continue;
		}

		// Inside an array: collect quoted strings until `]`.
		if (collecting)
		{
			collect(parseQuotedEntries(trimmed));
			if (trimmed.canFind(']'))
				collecting = false;
		}
	}

	paths = switches;
	return !switches.empty;
}

/**
 * Extracts all double-quoted strings from a fragment of an ldc2.conf
 * array entry, e.g. `"path", // comment` → `path`.
 */
private string[] parseQuotedEntries(string fragment)
{
	string[] entries;
	size_t i = 0;
	while (i < fragment.length)
	{
		auto start = fragment.indexOf('"', i);
		if (start == -1)
			break;
		auto end = fragment.indexOf('"', start + 1);
		if (end == -1)
			break;
		entries ~= fragment[start + 1 .. end];
		i = cast(size_t) (end + 1);
	}
	return entries;
}

// ---------------------------------------------------------------------------
// DMD config parsing
// ---------------------------------------------------------------------------

/**
 * Parses a `dmd.conf` (or Windows `sc.ini`) file: the
 * `[Environment64]`/`[Environment32]` sections' `DFLAGS=` line,
 * extracting `-I` entries and substituting `%@P%` with the conf file's
 * directory.
 */
private bool parseDmdConf(string confPath, ref string[] paths)
{
	enum Region { none, env32, env64 }

	auto confDir = confPath.dirName;
	Region match = Region.none;
	Region current = Region.none;
	string[] result;

	foreach (line; File(confPath).byLineCopy)
	{
		auto trimmed = line.strip;
		if (trimmed.empty)
			continue;

		if (sicmp(trimmed, "[Environment32]") == 0)
			current = Region.env32;
		else if (sicmp(trimmed, "[Environment64]") == 0)
			current = Region.env64;
		else if (trimmed.startsWith("DFLAGS=") && current >= match)
		{
			auto flags = trimmed["DFLAGS=".length .. $].stripLeft;
			result = parseDflagsImports(flags, confDir);
			match = current;
		}
	}

	paths = result;
	return !result.empty;
}

/**
 * Extracts `-I` paths from a `DFLAGS=` value, handling quoted arguments
 * and `%@P%` (conf directory) substitution.
 */
private string[] parseDflagsImports(string options, string confDir)
{
	string[] result;
	size_t i = 0;
	while (i < options.length)
	{
		auto idx = options.indexOf("-I", i);
		if (idx == -1)
			break;
		// Only accept -I at the start or preceded by whitespace/quote.
		if (idx > 0 && !isWhite(options[idx - 1]) && options[idx - 1] != '"')
		{
			i = cast(size_t) (idx + 2);
			continue;
		}
		i = cast(size_t) (idx + 2);
		// The path extends until the next whitespace or quote.
		size_t end = i;
		while (end < options.length && !isWhite(options[end]) && options[end] != '"')
			end++;
		auto path = options[i .. end].replace("%@P%", confDir);
		if (!path.empty)
			result ~= path;
		i = end;
	}
	return result;
}

// ---------------------------------------------------------------------------
// Hardcoded fallback
// ---------------------------------------------------------------------------

/**
 * Last-resort fallback: well-known install directories, used when no
 * compiler config could be found (e.g. a compiler installed without its
 * config file).
 */
private bool detectFromWellKnownPaths(ref string[] result)
{
	string[] candidates;

	// Homebrew LDC (Apple Silicon and Intel).
	foreach (cellar; ["/opt/homebrew/Cellar/ldc", "/usr/local/Cellar/ldc"])
	{
		if (exists(cellar) && isDir(cellar))
		{
			auto versions = dirEntries(cellar, SpanMode.shallow)
				.map!(a => a.name).array;
			sort!((a, b) => a > b)(versions); // newest first
			foreach (v; versions)
				candidates ~= buildPath(v, "include", "dlang", "ldc");
		}
	}

	// System-wide LDC.
	candidates ~= "/usr/local/include/dlang/ldc";
	candidates ~= "/usr/include/dlang/ldc";

	// dlang.org installers: ~/dlang/dmd-*/ and ~/dlang/ldc-*/.
	auto dlangDir = buildPath(environment.get("HOME", ""), "dlang");
	if (!dlangDir.empty && exists(dlangDir) && isDir(dlangDir))
	{
		auto dirs = dirEntries(dlangDir, SpanMode.shallow)
			.map!(a => a.name).array;
		sort!((a, b) => a > b)(dirs);
		foreach (d; dirs)
		{
			auto base = d.baseName;
			if (base.startsWith("dmd-"))
			{
				candidates ~= buildPath(d, "src", "phobos");
				candidates ~= buildPath(d, "src", "druntime", "import");
			}
			else if (base.startsWith("ldc-"))
			{
				candidates ~= buildPath(d, "import");
				candidates ~= buildPath(d, "include", "dlang", "ldc");
			}
		}
	}

	foreach (c; candidates)
		if (exists(buildPath(c, "std")))
		{
			result = [c];
			return true;
		}
	return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

version (unittest)
{
	import std.conv : to;

	unittest
	{
		// -I extraction from DFLAGS values.
		assert(parseDflagsImports(
			`-I/usr/include/dmd/phobos -I/usr/include/dmd/druntime/import -L-Lfoo`,
			"/etc") == ["/usr/include/dmd/phobos", "/usr/include/dmd/druntime/import"]);
		// %@P% substitution.
		assert(parseDflagsImports(`-I%@P%/../src/phobos`, "/opt/dmd") ==
			["/opt/dmd/../src/phobos"]);
		// -I embedded in another flag is not picked up.
		assert(parseDflagsImports(`-L-Ifoo`, "/etc").empty);
	}

	unittest
	{
		// Quoted entry extraction from ldc2.conf array fragments.
		assert(parseQuotedEntries(`"a", "b"`) == ["a", "b"]);
		assert(parseQuotedEntries(`"-I/path", // comment`) == ["-I/path"]);
		assert(parseQuotedEntries(`]`).empty);
	}

	unittest
	{
		// ldc2.conf parsing: default section, switches + post-switches,
		// %%ldcbinarypath%% substitution, non-default sections skipped.
		import std.file : mkdir, tempDir, rmdirRecurse;
		auto dir = buildPath(tempDir, "dcd-stdlib-test");
		mkdirRecurse(dir);
		scope (exit)
			rmdirRecurse(dir);

		auto conf = buildPath(dir, "ldc2.conf");
		std.file.write(conf, `
// comment
default:
{
    switches = [
        "-defaultlib=phobos2-ldc,druntime-ldc",
    ];
    post-switches = [
        "-I%%ldcbinarypath%%/../include/dlang/ldc",
    ];
    lib-dirs = [
        "%%ldcbinarypath%%/lib",
    ];
};

"^wasm(32|64)-":
{
    switches = [
        "-I/should/not/appear",
    ];
};
`);
		string[] paths;
		assert(parseLdcConf(conf, "/opt/homebrew/bin", paths));
		assert(paths == ["/opt/homebrew/bin/../include/dlang/ldc"], paths.to!string);
	}

	unittest
	{
		// dmd.conf parsing: Environment64 wins over Environment32.
		import std.file : mkdir, tempDir, rmdirRecurse;
		auto dir = buildPath(tempDir, "dcd-stdlib-test-dmd");
		mkdirRecurse(dir);
		scope (exit)
			rmdirRecurse(dir);

		auto conf = buildPath(dir, "dmd.conf");
		std.file.write(conf, `
[Environment32]
DFLAGS="-I/usr/lib/dmd/i386/phobos"
[Environment64]
DFLAGS="-I/usr/lib/dmd/amd64/phobos"
`);
		string[] paths;
		assert(parseDmdConf(conf, paths));
		assert(paths == ["/usr/lib/dmd/amd64/phobos"], paths.to!string);
	}
}
