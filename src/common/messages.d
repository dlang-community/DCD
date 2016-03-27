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

module common.messages;

import std.socket;
import msgpack;
import core.time : dur;

/**
 * The type of completion list being returned
 */
enum CompletionType : string
{
	/**
	 * The completion list contains a listing of identifier/kind pairs.
	 */
	identifiers = "identifiers",

	/**
	 * The auto-completion list consists of a listing of functions and their
	 * parameters.
	 */
	calltips = "calltips",

	/**
	 * The response contains the location of a symbol declaration.
	 */
	location = "location",

	/**
	 * The response contains documentation comments for the symbol.
	 */
	ddoc = "ddoc",
}

/**
 * Request kind
 */
enum RequestKind : ushort
{
	// dfmt off

	uninitialized =  0b00000000_00000000,
	/// Autocompletion
	autocomplete =   0b00000000_00000001,
	/// Clear the completion cache
	clearCache =     0b00000000_00000010,
	/// Add import directory to server
	addImport =      0b00000000_00000100,
	/// Shut down the server
	shutdown =       0b00000000_00001000,
	/// Get declaration location of given symbol
	symbolLocation = 0b00000000_00010000,
	/// Get the doc comments for the symbol
	doc =            0b00000000_00100000,
	/// Query server status
	query =	         0b00000000_01000000,
	/// Search for symbol
	search =         0b00000000_10000000,
	/// List import directories
	listImports =    0b00000001_00000000,

	// dfmt on
}

/**
 * Autocompletion request message
 */
struct AutocompleteRequest
{
	/**
	 * File name used for error reporting
	 */
	string fileName;

	/**
	 * Command coming from the client
	 */
	RequestKind kind;

	/**
	 * Paths to be searched for import files
	 */
	string[] importPaths;

	/**
	 * The source code to auto complete
	 */
	ubyte[] sourceCode;

	/**
	 * The cursor position
	 */
	size_t cursorPosition;

	/**
	 * Name of symbol searched for
	 */
	string searchName;
}

/**
 * Autocompletion response message
 */
struct AutocompleteResponse
{
	/**
	 * The autocompletion type. (Parameters or identifier)
	 */
	string completionType;

	/**
	 * The path to the file that contains the symbol.
	 */
	string symbolFilePath;

	/**
	 * The byte offset at which the symbol is located.
	 */
	size_t symbolLocation;

	/**
	 * The documentation comment
	 */
	string[] docComments;

	/**
	 * The completions
	 */
	string[] completions;

	/**
	 * The kinds of the items in the completions array. Will be empty if the
	 * completion type is a function argument list.
	 */
	char[] completionKinds;

	/**
	 * Symbol locations for symbol searches.
	 */
	size_t[] locations;

	/**
	 * Import paths that are registered by the server.
	 */
	string[] importPaths;
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

/**
 * Returns: true if a server instance is running
 * Params:
 *     useTCP = `true` to check a TCP port, `false` for UNIX domain socket
 *     socketFile = the file name for the UNIX domain socket
 *     port = the TCP port
 */
bool serverIsRunning(bool useTCP, string socketFile, ushort port)
{
	scope (failure)
		return false;
	AutocompleteRequest request;
	request.kind = RequestKind.query;
	Socket socket;
	scope (exit)
	{
		socket.shutdown(SocketShutdown.BOTH);
		socket.close();
	}
	version(Windows) useTCP = true;
	if (useTCP)
	{
		socket = new TcpSocket(AddressFamily.INET);
		socket.connect(new InternetAddress("localhost", port));
	}
	else
	{
		version(Windows) {} else
		{
			socket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
			socket.connect(new UnixAddress(socketFile));
		}
	}
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(5));
	socket.blocking = true;
	if (sendRequest(socket, request))
		return getResponse(socket).completionType == "ack";
	else
		return false;
}
