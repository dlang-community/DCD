/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2013 Brian Schott
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

module server;

import std.socket;
import std.stdio;
import std.getopt;
import std.algorithm;
import std.path;
import std.file;
import std.array;
import std.process;
import std.datetime;

import msgpack;

import messages;
import autocomplete;
import modulecache;
import stupidlog;
import actypes;
import core.memory;

enum CONFIG_FILE_NAME = "dcd.conf";

version(linux) version = useXDG;
version(BSD) version = useXDG;
version(FreeBSD) version = useXDG;
version(OSX) version = useXDG;

int main(string[] args)
{

	Log.info("Starting up...");
	StopWatch sw = StopWatch(AutoStart.yes);
	// No relative paths
	version (Posix) chdir("/");

	Log.output = stdout;
	Log.level = LogLevel.trace;

	ushort port = 9166;
	bool help;
	string[] importPaths;

	try
	{
		getopt(args, "port|p", &port, "I", &importPaths, "help|h", &help);
	}
	catch (Exception e)
	{
		stderr.writeln(e.msg);
		printHelp(args[0]);
		return 1;
	}

	if (help)
	{
		printHelp(args[0]);
		return 0;
	}

	importPaths ~= loadConfiguredImportDirs();

	auto socket = new TcpSocket(AddressFamily.INET);
	socket.blocking = true;
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
	socket.bind(new InternetAddress("localhost", port));
	socket.listen(0);
	scope (exit)
	{
		Log.info("Shutting down sockets...");
		socket.shutdown(SocketShutdown.BOTH);
		socket.close();
		Log.info("Sockets shut down.");
	}

	ModuleCache.addImportPaths(importPaths);
	Log.info("Import directories: ", ModuleCache.getImportPaths());

	ubyte[] buffer = new ubyte[1024 * 1024 * 4]; // 4 megabytes should be enough for anybody...

	sw.stop();
	Log.info("Startup completed in ", sw.peek().to!("msecs", float), " milliseconds");
	ModuleCache.estimateMemory();

	while (true)
	{
		auto s = socket.accept();
		s.blocking = true;

		// TODO: Restrict connections to localhost

		scope (exit)
		{
			s.shutdown(SocketShutdown.BOTH);
			s.close();
		}
		ptrdiff_t bytesReceived = s.receive(buffer);

		auto requestWatch = StopWatch(AutoStart.yes);

		size_t messageLength;
		// bit magic!
		(cast(ubyte*) &messageLength)[0..size_t.sizeof] = buffer[0..size_t.sizeof];
		while (bytesReceived < messageLength + size_t.sizeof)
		{
			auto b = s.receive(buffer[bytesReceived .. $]);
			if (b == Socket.ERROR)
			{
				bytesReceived = Socket.ERROR;
				break;
			}
			bytesReceived += b;
		}

		if (bytesReceived == Socket.ERROR)
		{
			Log.error("Socket recieve failed");
			break;
		}

		AutocompleteRequest request;
		msgpack.unpack(buffer[size_t.sizeof .. bytesReceived], request);
		if (request.kind == RequestKind.addImport)
		{
			ModuleCache.addImportPaths(request.importPaths);
		}
		else if (request.kind == RequestKind.clearCache)
		{
			Log.info("Clearing cache.");
			ModuleCache.clear();
		}
		else if (request.kind == RequestKind.shutdown)
		{
			Log.info("Shutting down.");
			break;
		}
		else
		{
			AutocompleteResponse response = complete(request, importPaths);
			ubyte[] responseBytes = msgpack.pack(response);
			assert(s.send(responseBytes) == responseBytes.length);
		}
		Log.info("Request processed in ", requestWatch.peek().to!("msecs", float), " milliseconds");
	}
	return 0;
}

string getConfigurationLocation()
{
	version (useXDG)
	{
		string configDir = environment.get("XDG_CONFIG_HOME", null);
		if (configDir is null)
		{
			configDir = environment.get("HOME", null);
			if (configDir is null)
				throw new Exception("Both $XDG_CONFIG_HOME and $HOME are unset");
			configDir = buildPath(configDir, ".config", "dcd", CONFIG_FILE_NAME);
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

void warnAboutOldConfigLocation()
{
	version (linux) if ("~/.config/dcd".expandTilde().exists()
		&& "~/.config/dcd".expandTilde().isFile())
	{
		Log.error("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
		Log.error("!! Upgrade warning:");
		Log.error("!! '~/.config/dcd' should be moved to '$XDG_CONFIG_HOME/dcd/dcd.conf'");
		Log.error("!! or '$HOME/.config/dcd/dcd.conf'");
		Log.error("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
	}
}

string[] loadConfiguredImportDirs()
{
	warnAboutOldConfigLocation();
	immutable string configLocation = getConfigurationLocation();
	if (!configLocation.exists())
		return [];
	Log.info("Loading configuration from ", configLocation);
	File f = File(configLocation, "rt");
	return f.byLine(KeepTerminator.no).map!(a => a.idup).filter!(a => a.exists()).array();
}

void printHelp(string programName)
{
    writefln(
`
    Usage: %s options

options:
    -I path
        Includes path in the listing of paths that are searched for file imports

    --port PORTNUMBER | -pPORTNUMBER
        Listens on PORTNUMBER instead of the default port 9166.`, programName);
}
