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

module dcd.client.client;

import std.socket;
import std.stdio;
import std.getopt;
import std.array;
import std.process;
import std.algorithm;
import std.path;
import std.file;
import std.conv;
import std.string;
import std.experimental.logger;

import dcd.common.messages;
import dcd.common.dcd_version;
import dcd.common.socket;

int main(string[] args)
{
	try
	{
		return runClient(args);
	}
	catch (Exception e)
	{
		stderr.writeln(e);
		return 1;
	}
}

private:

int runClient(string[] args)
{
	(cast()sharedLog).fatalHandler = () {};

	size_t cursorPos = size_t.max;
	string[] addedImportPaths;
	string[] removedImportPaths;
	ushort port;
	bool help;
	bool shutdown;
	bool clearCache;
	bool symbolLocation;
	bool doc;
	bool inlayHints;
	bool query;
	bool printVersion;
	bool listImports;
	bool getIdentifier;
	bool localUse;
	bool fullOutput;
	string search;
	version(Windows)
	{
		bool useTCP = true;
		string socketFile;
	}
	else
	{
		bool useTCP = false;
		string socketFile = generateSocketName();
	}

	try
	{
		getopt(args, "cursorPos|c", &cursorPos, "I", &addedImportPaths,
			"R", &removedImportPaths, "port|p", &port, "help|h", &help,
			"shutdown", &shutdown, "clearCache", &clearCache,
			"symbolLocation|l", &symbolLocation, "doc|d", &doc, "inlayHints", &inlayHints,
			"query|status|q", &query, "search|s", &search,
			"version", &printVersion, "listImports", &listImports,
			"tcp", &useTCP, "socketFile", &socketFile,
			"getIdentifier", &getIdentifier,
			"localUse|u", &localUse, "extended|x", &fullOutput);
	}
	catch (ConvException e)
	{
		fatal(e.msg);
		printHelp(args[0]);
		return 1;
	}

	AutocompleteRequest request;

	if (help)
	{
		printHelp(args[0]);
		return 0;
	}

	if (printVersion)
	{
		writeln(DCD_VERSION);
		return 0;
	}

	version (Windows) if (socketFile !is null)
	{
		fatal("UNIX domain sockets not supported on Windows");
		return 1;
	}

	// If the user specified a port number, assume that they wanted a TCP
	// connection. Otherwise set the port number to the default and let the
	// useTCP flag deterimen what to do later.
	if (port != 0)
		useTCP = true;
	else
		port = DEFAULT_PORT_NUMBER;

	if (useTCP)
		socketFile = null;

	if (query)
	{
		if (serverIsRunning(useTCP, socketFile, port))
		{
			writeln("Server is running");
			return 0;
		}
		else
		{
			writeln("Server is not running");
			return 1;
		}
	}
	else if (shutdown || clearCache)
	{
		if (shutdown)
		request.kind = RequestKind.shutdown;
		else if (clearCache)
			request.kind = RequestKind.clearCache;
		Socket socket = createSocket(socketFile, port);
		scope (exit) { socket.shutdown(SocketShutdown.BOTH); socket.close(); }
		if (!sendRequest(socket, request))
			return 1;
		return getResponse(socket).completionType == "ack" ? 0 : 2;
	}
	else if (addedImportPaths.length > 0 || removedImportPaths.length > 0)
	{
		immutable bool adding = addedImportPaths.length > 0;
		request.kind |= adding ? RequestKind.addImport : RequestKind.removeImport;
		request.importPaths = (adding ? addedImportPaths : removedImportPaths)
			.map!(a => absolutePath(a)).array;
		if (cursorPos == size_t.max)
		{
			Socket socket = createSocket(socketFile, port);
			scope (exit) { socket.shutdown(SocketShutdown.BOTH); socket.close(); }
			if (!sendRequest(socket, request))
				return 1;
			return getResponse(socket).completionType == "ack" ? 0 : 2;
		}
	}
	else if (listImports)
	{
		request.kind |= RequestKind.listImports;
		Socket socket = createSocket(socketFile, port);
		scope (exit) { socket.shutdown(SocketShutdown.BOTH); socket.close(); }
		if (!sendRequest(socket, request))
			return 1;
		AutocompleteResponse response = getResponse(socket);
		printImportList(response);
		return 0;
	}
	else if (search == null && cursorPos == size_t.max)
	{
		// cursor position is a required argument
		printHelp(args[0]);
		return 1;
	}

	// Read in the source
	immutable bool usingStdin = args.length <= 1;
	string fileName = usingStdin ? "stdin" : args[1];
	if (!usingStdin && !exists(args[1]))
	{
		stderr.writefln("%s does not exist", args[1]);
		return 1;
	}
	ubyte[] sourceCode;
	if (usingStdin)
	{
		ubyte[4096] buf;
		while (true)
		{
			auto b = stdin.rawRead(buf);
			if (b.length == 0)
				break;
			sourceCode ~= b;
		}
	}
	else
	{
		if (!exists(args[1]))
		{
			stderr.writeln("Could not find ", args[1]);
			return 1;
		}
		File f = File(args[1]);
		sourceCode = uninitializedArray!(ubyte[])(to!size_t(f.size));
		f.rawRead(sourceCode);
	}

	request.fileName = fileName;
	request.importPaths = addedImportPaths;
	request.sourceCode = sourceCode;
	request.cursorPosition = cursorPos;
	request.searchName = search;

	if (symbolLocation | getIdentifier)
		request.kind |= RequestKind.symbolLocation;
	else if (doc)
		request.kind |= RequestKind.doc;
	else if (search)
		request.kind |= RequestKind.search;
	else if(localUse)
		request.kind |= RequestKind.localUse;
    else if (inlayHints)
		request.kind |= RequestKind.inlayHints;
	else
		request.kind |= RequestKind.autocomplete;

	// Send message to server
	Socket socket = createSocket(socketFile, port);
	scope (exit) { socket.shutdown(SocketShutdown.BOTH); socket.close(); }
	if (!sendRequest(socket, request))
		return 1;

	AutocompleteResponse response = getResponse(socket);

	if (symbolLocation)
		printLocationResponse(response);
	else if (getIdentifier)
		printIdentifierResponse(response);
	else if (doc)
		printDocResponse(response, fullOutput);
	else if (search !is null)
		printSearchResponse(response);
	else if (localUse)
		printLocalUse(response);
	else if (inlayHints)
		printInlayHintsResponse(response);
	else
		printCompletionResponse(response, fullOutput);

	return 0;
}

void printHelp(string programName)
{
	writefln(
`
    Usage: %1$s [Options] [FILENAME]

    A file name is optional. If it is given, autocomplete information will be
    given for the file specified. If it is missing, input will be read from
    stdin instead.

    Source code is assumed to be UTF-8 encoded and must not exceed 4 megabytes.

Options:
    --help | -h
        Displays this help message

    --cursorPos | -c position
        Provides auto-completion at the given cursor position. The cursor
        position is measured in bytes from the beginning of the source code.

    --clearCache
        Instructs the server to clear out its autocompletion cache.

    --shutdown
        Instructs the server to shut down.

    --symbolLocation | -l
        Get the file name and position that the symbol at the cursor location
        was defined.

    --doc | -d
        Gets documentation comments associated with the symbol at the cursor
        location.

    --search | -s symbolName
        Searches for symbolName in both stdin / the given file name as well as
        others files cached by the server.

    --localUse | -u
        Searches for all the uses of the symbol at the cursor location
        in the given filename (or stdin).

    --extended | -x
        Includes more information with a slightly different format for
        calltips when autocompleting.

    --query | -q | --status
        Query the server statis. Returns 0 if the server is running. Returns
        1 if the server could not be contacted.

    -I PATH
        Instructs the server to add PATH to its list of paths searched for
        imported modules.

    --version
        Prints the version number and then exits.

    --port PORTNUMBER | -p PORTNUMBER
        Uses PORTNUMBER to communicate with the server instead of the default
        port 9166. Only used on Windows or when the --tcp option is set.

    --tcp
        Send requests on a TCP socket instead of a UNIX domain socket. This
        switch has no effect on Windows.

    --socketFile FILENAME
        Use the given FILENAME as the path to the UNIX domain socket. Using
        this switch is an error on Windows.`, programName);
}

Socket createSocket(string socketFile, ushort port)
{
	import core.time : dur;

	Socket socket;
	if (socketFile is null)
	{
		socket = new TcpSocket(AddressFamily.INET);
		socket.connect(new InternetAddress("localhost", port));
	}
	else
	{
		version(Windows)
		{
			// should never be called with non-null socketFile on Windows
			assert(false);
		}
		else
		{
			socket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
			socket.connect(new UnixAddress(socketFile));
		}
	}
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(5));
	socket.blocking = true;
	return socket;
}

void printDocResponse(ref const AutocompleteResponse response, bool extended)
{
	foreach (ref completion; response.completions)
	{
		if (extended)
			writeln(completion.definition);
		writeln(completion.documentation.escapeConsoleOutputString(true));
	}
}

void printIdentifierResponse(ref const AutocompleteResponse response)
{
	if (response.completions.length == 0)
		return;
	writeln(makeTabSeparated(response.completions[0].identifier, response.symbolIdentifier.to!string));
}

void printLocationResponse(ref const AutocompleteResponse response)
{
	if (response.symbolFilePath is null)
		writeln("Not found");
	else
		writeln(makeTabSeparated(response.symbolFilePath, response.symbolLocation.to!string));
}

void printInlayHintsResponse(ref const AutocompleteResponse response)
{
	auto app = appender!(string[])();
	foreach (ref completion; response.completions)
    {
        app.put(makeTabSeparated(completion.symbolLocation.to!string, completion.identifier));
    }
	foreach (line; app.data)
		writeln(line);
}

void printCompletionResponse(ref const AutocompleteResponse response, bool extended)
{
	if (response.completions.length > 0)
	{
		writeln(response.completionType);
		auto app = appender!(string[])();
		if (response.completionType == CompletionType.identifiers || extended)
		{
			foreach (ref completion; response.completions)
			{
				if (extended)
					app.put(makeTabSeparated(
						completion.identifier,
						completion.kind == char.init ? "" : "" ~ completion.kind,
						completion.definition,
						completion.symbolFilePath.length ? completion.symbolFilePath ~ " " ~ completion.symbolLocation.to!string : "",
						completion.documentation,
						completion.typeOf
					));
				else
					app.put(makeTabSeparated(completion.identifier, "" ~ completion.kind));
			}
		}
		else
		{
			foreach (completion; response.completions)
				app.put(completion.definition);
		}
		// Deduplicate overloaded methods
		foreach (line; app.data.sort().uniq)
			writeln(line);
	}
}

void printSearchResponse(const AutocompleteResponse response)
{
	foreach(ref completion; response.completions)
		writeln(makeTabSeparated(completion.symbolFilePath, "" ~ completion.kind, completion.symbolLocation.to!string));
}

void printLocalUse(const AutocompleteResponse response)
{
	if (response.symbolFilePath.length)
	{
		writeln(makeTabSeparated(response.symbolFilePath, response.symbolLocation.to!string));
		foreach(loc; response.completions)
			writeln(loc.symbolLocation);
	}
	else write("00000");
}

void printImportList(const AutocompleteResponse response)
{
	import std.algorithm.iteration : each;

	response.importPaths.each!(a => writeln(a));
}
