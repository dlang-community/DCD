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

module client.client;

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

import msgpack;
import common.messages;
import common.dcd_version;
import common.socket;

int main(string[] args)
{
	size_t cursorPos = size_t.max;
	string[] importPaths;
	ushort port = 9166;
	bool help;
	bool shutdown;
	bool clearCache;
	bool symbolLocation;
	bool doc;
	bool query;
	bool printVersion;
	bool listImports;
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
		getopt(args, "cursorPos|c", &cursorPos, "I", &importPaths,
			"port|p", &port, "help|h", &help, "shutdown", &shutdown,
			"clearCache", &clearCache, "symbolLocation|l", &symbolLocation,
			"doc|d", &doc, "query|status|q", &query, "search|s", &search,
			"version", &printVersion, "listImports", &listImports,
			"tcp", &useTCP, "socketFile", &socketFile);
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
		version (Windows)
			writeln(DCD_VERSION);
		else version(built_with_dub)
			writeln(DCD_VERSION);
		else
			write(DCD_VERSION, " ", GIT_HASH);
		return 0;
	}

	version (Windows) if (socketFile !is null)
	{
		fatal("UNIX domain sockets not supported on Windows");
		return 1;
	}

	if (useTCP)
		socketFile = null;

	if (query)
	{
		try
		{
			Socket socket = createSocket(socketFile, port);
			scope (exit) { socket.shutdown(SocketShutdown.BOTH); socket.close(); }
			request.kind = RequestKind.query;
			if (sendRequest(socket, request))
			{
				const AutocompleteResponse response = getResponse(socket);
				if (response.completionType == "ack")
				{
					writeln("Server is running");
					return 0;
				}
				else
					throw new Exception("");
			}
		}
		catch (Exception ex)
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
		return sendRequest(socket, request) ? 0 : 1;
	}
	else if (importPaths.length > 0)
	{
		request.kind |= RequestKind.addImport;
		request.importPaths = importPaths.map!(a => absolutePath(a)).array;
		if (cursorPos == size_t.max)
		{
			Socket socket = createSocket(socketFile, port);
			scope (exit) { socket.shutdown(SocketShutdown.BOTH); socket.close(); }
			if (!sendRequest(socket, request))
				return 1;
			return 0;
		}
	}
	else if (listImports)
	{
		request.kind |= RequestKind.listImports;
		Socket socket = createSocket(socketFile, port);
		scope (exit) { socket.shutdown(SocketShutdown.BOTH); socket.close(); }
		sendRequest(socket, request);
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
	request.importPaths = importPaths;
	request.sourceCode = sourceCode;
	request.cursorPosition = cursorPos;
	request.searchName = search;

	if (symbolLocation)
		request.kind |= RequestKind.symbolLocation;
	else if (doc)
		request.kind |= RequestKind.doc;
	else if(search)
		request.kind |= RequestKind.search;
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
	else if (doc)
		printDocResponse(response);
	else if (search !is null)
		printSearchResponse(response);
	else
		printCompletionResponse(response);

	return 0;
}

private:

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

/**
 * Returns: true on success
 */
bool sendRequest(Socket socket, AutocompleteRequest request)
{
	ubyte[] message = msgpack.pack(request);
	ubyte[] messageBuffer = new ubyte[message.length + message.length.sizeof];
	auto messageLength = message.length;
	messageBuffer[0 .. size_t.sizeof] = (cast(ubyte*) &messageLength)[0 .. size_t.sizeof];
	messageBuffer[size_t.sizeof .. $] = message[];
	return socket.send(messageBuffer) == messageBuffer.length;
}

/**
 * Gets the response from the server
 */
AutocompleteResponse getResponse(Socket socket)
{
	ubyte[1024 * 16] buffer;
	auto bytesReceived = socket.receive(buffer);
	if (bytesReceived == Socket.ERROR)
		throw new Exception("Incorrect number of bytes received");
	if (bytesReceived == 0)
		throw new Exception("Server closed the connection, 0 bytes received");
	AutocompleteResponse response;
	msgpack.unpack(buffer[0..bytesReceived], response);
	return response;
}

void printDocResponse(AutocompleteResponse response)
{
	import std.array: join;
    response.docComments.join(r"\n\n").writeln;
}

void printLocationResponse(AutocompleteResponse response)
{
	if (response.symbolFilePath is null)
		writeln("Not found");
	else
		writefln("%s\t%d", response.symbolFilePath, response.symbolLocation);
}

void printCompletionResponse(AutocompleteResponse response)
{
	if (response.completions.length > 0)
	{
		writeln(response.completionType);
		auto app = appender!(string[])();
		if (response.completionType == CompletionType.identifiers)
		{
			for (size_t i = 0; i < response.completions.length; i++)
				app.put(format("%s\t%s", response.completions[i], response.completionKinds[i]));
		}
		else
		{
			foreach (completion; response.completions)
			{
				app.put(completion);
			}
		}
		// Deduplicate overloaded methods
		foreach (line; app.data.sort().uniq)
			writeln(line);
	}
}

void printSearchResponse(const AutocompleteResponse response)
{
	foreach(i; 0 .. response.completions.length)
	{
		writefln("%s\t%s\t%s", response.completions[i], response.completionKinds[i],
			response.locations[i]);
	}
}

void printImportList(const AutocompleteResponse response)
{
	import std.algorithm.iteration : each;

	response.importPaths.each!(a => writeln(a));
}
