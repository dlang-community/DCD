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

module dcd.server.lsp.jsonrpc;

import core.stdc.stdio : fgetc, EOF;
import core.sync.mutex : Mutex;
import std.algorithm;
import std.array;
import std.conv;
import std.exception : enforce;
import std.json;
import std.stdio;
import std.string : indexOf, toLower, strip;

/**
 * A JSON-RPC 2.0 message (request, notification, or response) in parsed form.
 */
struct JsonRpcMessage
{
	/// True if the stream ended before a complete message was read.
	bool endOfStream;

	/// The method name, `null` for responses.
	string method;

	/// The request id as a string, `null` if absent (notification or response).
	string id;

	/// The raw JSON id value, preserved with its original type (number or
	/// string) so responses echo it back exactly as the client sent it.
	/// JSON-RPC 2.0 requires the response id to match the request id including
	/// its type; converting a numeric id to a string makes clients like
	/// vscode-jsonrpc unable to match responses to pending requests.
	JSONValue rawId;

	/// True if the message carries an id (request or response).
	bool hasId;

	/// The params object.
	JSONValue params;

	/// True if the message has a params member.
	bool hasParams;

	/// True if this message is a request (has method and id).
	bool isRequest() const
	{
		return method !is null && id !is null;
	}

	/// True if this message is a notification (has method, no id).
	bool isNotification() const
	{
		return method !is null && id is null;
	}

	/// True if this message is a response (no method).
	bool isResponse() const
	{
		return method is null;
	}
}

/**
 * Reads LSP messages framed with `Content-Length` headers from stdin.
 *
 * The header is read byte-by-byte (headers are tiny) because buffered chunk
 * reads like `stdin.byChunk` block until a full chunk arrives, which would
 * hang on an interactive pipe. The body is then read with a single exact-size
 * read, which correctly blocks until the whole message has arrived.
 *
 * All reads go through the RAW file descriptor (core.sys.posix.unistd.read),
 * not the stdio FILE*: fgetc/rawRead hold the FILE lock while blocked, and
 * std.process.spawnProcess calls fileno() on stdin/stdout/stderr, which
 * needs that same lock — a background thread spawning a process (e.g. the
 * D-Scanner linter) would deadlock against a main thread blocked in fgetc
 * waiting for the next message. Raw fd reads carry no lock.
 *
 * Returns a message with `endOfStream == true` on end of stream.
 */
JsonRpcMessage readMessage()
{
	version (Posix)
	{
		import core.sys.posix.unistd : read;
		immutable fd = stdin.fileno;

		// Reads one byte from the raw stdin fd; -1 on error/EOF.
		int readByte()
		{
			ubyte[1] buf;
			while (true)
			{
				immutable n = read(fd, buf.ptr, 1);
				if (n == 1)
					return buf[0];
				if (n == 0)
					return -1; // EOF
				import core.stdc.errno : errno, EINTR;
				if (errno == EINTR)
					continue; // interrupted, retry
				return -1; // hard error, treat as EOF
			}
		}

		// Reads exactly buf.length bytes; false on EOF mid-message.
		bool readExact(ubyte[] buf)
		{
			size_t filled;
			while (filled < buf.length)
			{
				immutable n = read(fd, buf.ptr + filled, buf.length - filled);
				if (n == 0)
					return false; // EOF
				if (n < 0)
				{
					import core.stdc.errno : errno, EINTR;
					if (errno == EINTR)
						continue;
					return false;
				}
				filled += n;
			}
			return true;
		}
	}
	else
	{
		import core.stdc.stdio : fgetc;
		int readByte()
		{
			return fgetc(stdin.getFP());
		}
		bool readExact(ubyte[] buf)
		{
			auto got = stdin.rawRead(buf);
			return got.length == buf.length;
		}
	}

	// Read the header byte-by-byte until \r\n\r\n
	auto headerBuffer = appender!(char[])();
	bool foundTerminator;
	while (true)
	{
		const int c = readByte();
		if (c == EOF)
			return JsonRpcMessage(true);
		headerBuffer.put(cast(char) c);
		auto data = headerBuffer.data;
		if (data.length >= 4
			&& data[$ - 4] == '\r' && data[$ - 3] == '\n'
			&& data[$ - 2] == '\r' && data[$ - 1] == '\n')
		{
			foundTerminator = true;
			break;
		}
		// sanity limit to avoid unbounded memory on a malformed stream
		if (data.length > 16 * 1024)
			throw new Exception("LSP message header too long");
	}
	enforce(foundTerminator, "Missing header terminator in LSP message");

	// Parse Content-Length from the header
	const headerText = headerBuffer.data[0 .. $ - 4];
	size_t contentLength;
	bool foundLength;
	foreach (line; headerText.splitter('\n'))
	{
		auto trimmed = line.stripRight!(a => a == '\r');
		auto colon = trimmed.indexOf(':');
		if (colon < 0)
			continue;
		auto name = trimmed[0 .. colon].toLower.strip;
		if (name == "content-length")
		{
			contentLength = trimmed[colon + 1 .. $].strip.to!size_t;
			foundLength = true;
		}
	}
	enforce(foundLength, "Missing Content-Length header in LSP message");

	// Read exactly contentLength bytes for the body. This blocks until the
	// full message has arrived, which is correct: the message is incomplete
	// until then. A short read means the stream ended mid-message.
	auto body = new ubyte[contentLength];
	if (!readExact(body))
		return JsonRpcMessage(true);

	return parseMessage((cast(string) body).parseJSON());
}

/**
 * Parses a JSON value into a `JsonRpcMessage`.
 */
JsonRpcMessage parseMessage(JSONValue json)
{
	JsonRpcMessage message;
	if ("method" in json)
		message.method = json["method"].str;
	if ("id" in json)
	{
		auto id = json["id"];
		if (id.type == JSONType.integer)
			message.id = id.integer.to!string;
		else if (id.type == JSONType.string)
			message.id = id.str;
		else if (id.type == JSONType.null_)
			message.id = null;
		message.rawId = id;
		message.hasId = true;
	}
	if ("params" in json)
	{
		message.params = json["params"];
		message.hasParams = true;
	}
	return message;
}

/**
 * Writes raw JSON text framed with a `Content-Length` header to stdout.
 */
void writeMessageRaw(string jsonText)
{
	stdout.rawWrite("Content-Length: " ~ jsonText.length.to!string ~ "\r\n\r\n" ~ jsonText);
	stdout.flush();
}

/**
 * Builds a JSON-RPC response object.
 *
 * The id is echoed back with its original type (number or string) as required
 * by JSON-RPC 2.0. Passing a message's `rawId` preserves the client's type.
 */
JSONValue makeResponse(JSONValue id, JSONValue result)
{
	JSONValue response = parseJSON(`{"jsonrpc":"2.0"}`);
	response["id"] = id.type == JSONType.null_ ? JSONValue(null) : id;
	response["result"] = result;
	return response;
}

/**
 * Builds a JSON-RPC error response object.
 *
 * The id is echoed back with its original type (number or string) as required
 * by JSON-RPC 2.0.
 */
JSONValue makeErrorResponse(JSONValue id, int code, string message)
{
	JSONValue response = parseJSON(`{"jsonrpc":"2.0"}`);
	response["id"] = id.type == JSONType.null_ ? JSONValue(null) : id;
	JSONValue error = parseJSON(`{}`);
	error["code"] = JSONValue(code);
	error["message"] = JSONValue(message);
	response["error"] = error;
	return response;
}

/**
 * Builds a JSON-RPC notification object (no id).
 */
JSONValue makeNotification(string method, JSONValue params)
{
	JSONValue request = parseJSON(`{"jsonrpc":"2.0"}`);
	request["method"] = JSONValue(method);
	if (params.type == JSONType.object)
		request["params"] = params;
	return request;
}

/**
 * Counter for server -> client request ids. Server-originated requests use
 * negative ids so they can never collide with the client's request ids
 * (which start at 0 and count up).
 */
private long nextServerRequestId()
{
	static __gshared long counter;
	static __gshared Mutex counterMutex;
	if (counterMutex is null)
		counterMutex = new Mutex;
	synchronized (counterMutex)
		return --counter;
}

/**
 * Builds a JSON-RPC request object (with id) sent from the server to the
 * client, e.g. `workspace/applyEdit`.
 */
JSONValue makeServerRequest(string method, JSONValue params)
{
	JSONValue request = parseJSON(`{"jsonrpc":"2.0"}`);
	request["id"] = JSONValue(nextServerRequestId());
	request["method"] = JSONValue(method);
	if (params.type == JSONType.object)
		request["params"] = params;
	return request;
}

/**
 * Sends a server -> client request and returns immediately, without
 * waiting for the response. The response (if the client sends one) is
 * ignored by the main loop; fire-and-forget is the right model for
 * `workspace/applyEdit`, where the edit is advisory and the client may
 * reject it (e.g. the user undid, the document changed).
 */
void sendServerRequest(string method, JSONValue params)
{
	writeMessageRaw(makeServerRequest(method, params).toString());
}

/**
 * Standard JSON-RPC 2.0 error codes.
 */
enum JsonRpcErrorCode
{
	parseError = -32700,
	invalidRequest = -32600,
	methodNotFound = -32601,
	invalidParams = -32602,
	internalError = -32603,
	/// LSP: server not initialized
	serverNotInitialized = -32002,
	/// LSP: request cancelled
	requestCancelled = -32800,
}

unittest
{
	// Test message parsing
	auto json = parseJSON(`{"jsonrpc":"2.0","id":1,"method":"test","params":{}}`);
	auto message = parseMessage(json);
	assert(message.isRequest);
	assert(message.method == "test");
	assert(message.id == "1");
	assert(message.hasParams);

	// Test notification parsing
	auto notif = parseJSON(`{"jsonrpc":"2.0","method":"notify"}`);
	auto notifMessage = parseMessage(notif);
	assert(notifMessage.isNotification);
	assert(!notifMessage.isRequest);

	// Test response building
	auto response = makeResponse(JSONValue(1), JSONValue(null));
	assert(response["result"].type == JSONType.null_);
	assert(response["id"].type == JSONType.integer);
	assert(response["id"].integer == 1);

	// Test that numeric ids keep their type (JSON-RPC 2.0 requirement)
	auto numericIdJson = parseJSON(`{"jsonrpc":"2.0","id":42,"method":"m"}`);
	auto numericMessage = parseMessage(numericIdJson);
	assert(numericMessage.rawId.type == JSONType.integer);
	assert(numericMessage.rawId.integer == 42);
	auto numericResponse = makeResponse(numericMessage.rawId, JSONValue(null));
	assert(numericResponse["id"].type == JSONType.integer);
	assert(numericResponse["id"].integer == 42);

	// String ids stay strings
	auto stringIdJson = parseJSON(`{"jsonrpc":"2.0","id":"abc","method":"m"}`);
	auto stringMessage = parseMessage(stringIdJson);
	auto stringResponse = makeResponse(stringMessage.rawId, JSONValue(null));
	assert(stringResponse["id"].type == JSONType.string);
	assert(stringResponse["id"].str == "abc");
}
