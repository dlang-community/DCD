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

module client;

import std.socket;
import std.stdio;
import std.getopt;
import std.array;

import msgpack;
import messages;

int main(string[] args)
{
    size_t cursorPos = size_t.max;
    string[] importPaths;
    ushort port = 9166;
    bool help;
	bool shutdown;
	bool clearCache;

    try
    {
        getopt(args, "cursorPos|c", &cursorPos, "I", &importPaths,
			"port|p", &port, "help|h", &help, "shutdown", &shutdown,
			"clearCache", &clearCache);
    }
    catch (Exception e)
    {
        stderr.writeln(e.msg);
    }

    if (help)
    {
        printHelp(args[0]);
        return 0;
	}

	if (shutdown || clearCache)
	{
		AutocompleteRequest request;
		if (shutdown)
		request.kind = RequestKind.shutdown;
		else if (clearCache)
			request.kind = RequestKind.clearCache;
		auto socket = new TcpSocket(AddressFamily.INET);
		scope (exit) { socket.shutdown(SocketShutdown.BOTH); socket.close(); }
		socket.connect(new InternetAddress("127.0.0.1", port));
		socket.blocking = true;
		socket.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, 1);
		ubyte[] message = msgpack.pack(request);
		ubyte[] messageBuffer = new ubyte[message.length + message.length.sizeof];
		auto messageLength = message.length;
		messageBuffer[0 .. 8] = (cast(ubyte*) &messageLength)[0 .. 8];
		messageBuffer[8 .. $] = message[];
		return socket.send(messageBuffer) == messageBuffer.length ? 0 : 1;
    }

    // cursor position is a required argument
    if (cursorPos == size_t.max)
    {
        printHelp(args[0]);
        return 1;
    }

    // Read in the source
    bool usingStdin = args.length <= 1;
    string fileName = usingStdin ? "stdin" : args[1];
    File f = usingStdin ? stdin : File(args[1]);
    ubyte[] sourceCode;
    if (usingStdin)
	{
		ubyte[4096] buf;
		while (true)
		{
			auto b = f.rawRead(buf);
			if (b.length == 0)
				break;
			sourceCode ~= b;
		}
	}
	else
	{
		sourceCode = uninitializedArray!(ubyte[])(f.size);
		f.rawRead(sourceCode);
	}

    // Create message
    AutocompleteRequest request;
    request.fileName = fileName;
    request.importPaths = importPaths;
    request.sourceCode = sourceCode;
    request.cursorPosition = cursorPos;
    ubyte[] message = msgpack.pack(request);

    // Send message to server
    auto socket = new TcpSocket(AddressFamily.INET);
    scope (exit) { socket.shutdown(SocketShutdown.BOTH); socket.close(); }
    socket.connect(new InternetAddress("127.0.0.1", port));
    socket.blocking = true;
    socket.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, 1);
    ubyte[] messageBuffer = new ubyte[message.length + message.length.sizeof];
    auto messageLength = message.length;
    messageBuffer[0 .. 8] = (cast(ubyte*) &messageLength)[0 .. 8];
    messageBuffer[8 .. $] = message[];
    auto bytesSent = socket.send(messageBuffer);

    // Get response and write it out
    ubyte[1024 * 16] buffer;
    auto bytesReceived = socket.receive(buffer);
    if (bytesReceived == Socket.ERROR)
    {
        return 1;
    }

    AutocompleteResponse response;
    msgpack.unpack(buffer[0..bytesReceived], response);

    writeln(response.completionType);
    if (response.completionType == CompletionType.identifiers)
    {
        for (size_t i = 0; i < response.completions.length; i++)
        {
            writefln("%s\t%s", response.completions[i], response.completionKinds[i]);
        }
    }
    else
    {
        foreach (completion; response.completions)
        {
            writeln(completion);
        }
    }
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

    -IPATH
        Instructs the server to add PATH to its list of paths searced for
        imported modules.

    --port PORTNUMBER | -pPORTNUMBER
        Uses PORTNUMBER to communicate with the server instead of the default
        port 9166.`, programName);
}
