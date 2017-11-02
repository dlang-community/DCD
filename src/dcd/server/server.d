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

module dcd.server.server;

import std.algorithm;
import std.array;
import std.experimental.logger;
import std.file;
import std.path;
import std.process: environment;
import std.stdio: File;
import std.stdio: KeepTerminator;

import dsymbol.modulecache;

/// Name of the server configuration file
enum CONFIG_FILE_NAME = "dcd.conf";

version(linux) version = useXDG;
version(BSD) version = useXDG;
version(FreeBSD) version = useXDG;
version(OSX) version = useXDG;

/**
 * Locates the configuration file
 */
string getConfigurationLocation()
{
	version (useXDG)
	{
		string configDir = environment.get("XDG_CONFIG_HOME", null);
		if (configDir is null)
		{
			configDir = environment.get("HOME", null);
			if (configDir !is null)
				configDir = buildPath(configDir, ".config", "dcd", CONFIG_FILE_NAME);
			if (!exists(configDir))
				configDir = buildPath("/etc/", CONFIG_FILE_NAME);
		}
		else
		{
			configDir = buildPath(configDir, "dcd", CONFIG_FILE_NAME);
		}
		return configDir;
	}
	else version(Windows)
	{
		return CONFIG_FILE_NAME;
	}
}

import std.regex : ctRegex;
alias envVarRegex = ctRegex!(`\$\{([_a-zA-Z][_a-zA-Z 0-9]*)\}`);

private unittest
{
	import std.regex : replaceAll;

	enum input = `${HOME}/aaa/${_bb_b}/ccc`;

	assert(replaceAll!(m => m[1])(input, envVarRegex) == `HOME/aaa/_bb_b/ccc`);
}

/**
 * Loads import directories from the configuration file
 */
string[] loadConfiguredImportDirs()
{
	string expandEnvVars(string l)
	{
		import std.regex : replaceAll;
		return replaceAll!(m => environment.get(m[1], ""))(l, envVarRegex);
	}

	immutable string configLocation = getConfigurationLocation();
	if (!configLocation.exists())
		return [];
	info("Loading configuration from ", configLocation);
	File f = File(configLocation, "rt");
	return f.byLine(KeepTerminator.no)
		.filter!(a => a.length > 0 && a[0] != '#')
		.map!(a => a.idup)
		.map!(expandEnvVars)
		.filter!(a => existanceCheck(a))
		.array();
}
