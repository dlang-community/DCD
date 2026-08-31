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
 * Returns a message with `endOfStream == true` on end of stream.
 */
JsonRpcMessage readMessage()
{
	// Read the header byte-by-byte until \r\n\r\n
	auto headerBuffer = appender!(char[])();
	bool foundTerminator;
	while (true)
	{
		const int c = fgetc(stdin.getFP());
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
	auto body = stdin.rawRead(new ubyte[contentLength]);
	if (body.length < contentLength)
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
 */
JSONValue makeResponse(string id, JSONValue result)
{
	JSONValue response = parseJSON(`{"jsonrpc":"2.0"}`);
	response["id"] = id.length ? JSONValue(id) : JSONValue(null);
	response["result"] = result;
	return response;
}

/**
 * Builds a JSON-RPC error response object.
 */
JSONValue makeErrorResponse(string id, int code, string message)
{
	JSONValue response = parseJSON(`{"jsonrpc":"2.0"}`);
	response["id"] = id.length ? JSONValue(id) : JSONValue(null);
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
	auto response = makeResponse("1", JSONValue(null));
	assert(response["result"].type == JSONType.null_);
}
