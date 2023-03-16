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

module dcd.common.messages;

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
	/// Local symbol usage
	localUse =     	 0b00000010_00000000,
	/// Remove import directory from server
	removeImport =   0b00000100_00000000,

	/// These request kinds require source code and won't be executed if there
	/// is no source sent
	requiresSourceCode = autocomplete | doc | symbolLocation | search | localUse,
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
	static struct Completion
	{
		/**
		 * The name of the symbol for a completion, for calltips just the function name.
		 */
		string identifier;
		/**
		 * The kind of the item. Will be char.init for calltips.
		 */
		ubyte kind;
		/**
		 * Definition for a symbol for a completion including attributes or the arguments for calltips.
		 */
		string definition;
		/**
		 * The path to the file that contains the symbol.
		 */
		string symbolFilePath;
		/**
		 * The byte offset at which the symbol is located or symbol location for symbol searches.
		 */
		size_t symbolLocation;
		/**
		 * Documentation associated with this symbol.
		 */
		string documentation;
		// when changing the behavior here, update README.md
		/**
		 * For variables, fields, globals, constants: resolved type or empty if unresolved.
		 * For functions: resolved return type or empty if unresolved.
		 * For constructors: may be struct/class name or empty in any case.
		 * Otherwise (probably) empty.
		 */
		string typeOf;
	}

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
	 * The completions
	 */
	Completion[] completions;

	/**
	 * Import paths that are registered by the server.
	 */
	string[] importPaths;

	/**
	 * Symbol identifier
	 */
	ulong symbolIdentifier;

	/**
	 * Creates an empty acknowledgement response
	 */
	static AutocompleteResponse ack()
	{
		AutocompleteResponse response;
		response.completionType = "ack";
		return response;
	}
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
	size_t i;
	while (i < messageBuffer.length)
	{
		auto sent = socket.send(messageBuffer[i .. $]);
		if (sent == Socket.ERROR)
			return false;
		i += sent;
	}
	return true;
}

/**
 * Gets the response from the server
 */
AutocompleteResponse getResponse(Socket socket)
{
	ubyte[1024 * 16] buffer;
	ptrdiff_t bytesReceived = 0;
	auto unpacker = StreamingUnpacker([]);

	do {
		bytesReceived = socket.receive(buffer);
		if (bytesReceived == Socket.ERROR)
			throw new Exception(lastSocketError);
		if (bytesReceived == 0)
			break;
		unpacker.feed(buffer[0..bytesReceived]);
	} while (true);

	if (unpacker.size == 0)
		throw new Exception("Server closed the connection, 0 bytes received");

	if (!unpacker.execute())
		throw new Exception("Could not unpack the response");

	return unpacker.purge().value.as!AutocompleteResponse;
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

/// Escapes \n, \t and \ in the string. If `single` is true \t won't be escaped.
/// Params:
///   s = the string to escape
///   single = if true, `s` is already tab separated and only needs to be escape new lines.
///            Otherwise `s` is treated as one value that is meant to be printed tab separated with other values.
/// Returns: An escaped string that is safe to print to the console so it can be read line by line
string escapeConsoleOutputString(string s, bool single = false)
{
	import std.array : Appender;

	Appender!(char[]) app;
	void putChar(char c)
	{
		switch (c)
		{
		case '\\':
			app.put('\\');
			app.put('\\');
			break;
		case '\n':
			app.put('\\');
			app.put('n');
			break;
		case '\t':
			if (single)
				goto default;
			else
			{
				app.put('\\');
				app.put('t');
				break;
			}
		default:
			app.put(c);
			break;
		}
	}

	foreach (char c; s)
		putChar(c);

	return app.data.idup;
}

/// Joins string arguments with tabs and escapes them
string makeTabSeparated(string[] args...)
{
	import std.algorithm : map;
	import std.array : join;

	return args.map!(a => a.escapeConsoleOutputString).join("\t");
}
