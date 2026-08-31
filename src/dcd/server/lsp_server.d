module dcd.server.lsp_server;

import std.algorithm;
import std.array;
import std.conv;
import std.experimental.logger;
import std.json;
import std.stdio;

import dcd.server.lsp.jsonrpc;
import dcd.server.lsp.protocol;
import dcd.server.lsp.document;
import dcd.server.lsp.handlers;

import dsymbol.modulecache;

/**
 * The lifecycle state of the LSP server.
 */
enum LifecycleState
{
	/// Waiting for the `initialize` request.
	uninitialized,
	/// `initialize` received, waiting for `initialized` notification.
	initializing,
	/// Normal operation.
	running,
	/// `shutdown` received, waiting for `exit` notification.
	shutdownReceived,
	/// Terminal state after `exit`.
	exited,
}

/**
 * Runs the LSP server over stdin/stdout.
 *
 * Params:
 *     importPaths = import paths to pre-load into the module cache
 *     ignoreConfig = skip loading `dcd.conf`
 * Returns:
 *     the process exit code
 */
int runLspServer(string[] importPaths, bool ignoreConfig)
{
	info("Starting DCD LSP server");

	ModuleCache cache;
	cache.addImportPaths(importPaths);
	if (!ignoreConfig)
	{
		import dcd.server.server : loadConfiguredImportDirs;
		cache.addImportPaths(loadConfiguredImportDirs());
	}

	ServerContext context;
	context.cache = &cache;
	context.documents = new DocumentStore(PositionEncoding.utf8);
	context.converter = PositionConverter(PositionEncoding.utf8);

	LifecycleState state = LifecycleState.uninitialized;

	while (true)
	{
		auto message = readMessage();
		if (message.endOfStream)
		{
			// End of stream: exit per spec
			info("Input stream closed, exiting");
			return state == LifecycleState.shutdownReceived ? 0 : 1;
		}

		if (message.isResponse())
		{
			// A response from the client (e.g. to a server->client request);
			// we don't send any, so just ignore it.
			continue;
		}

		final switch (state)
		{
		case LifecycleState.uninitialized:
			if (message.method == "initialize")
			{
				auto result = handleRequest(context, message.method, message.params);
			sendHandlerResult(message.rawId, result);
			state = LifecycleState.initializing;
		}
		else if (message.method == "exit")
		{
			info("Exit before initialize");
			return 1;
		}
		else if (message.isRequest)
		{
			// Per spec: requests before initialize are rejected
			sendJson(makeErrorResponse(message.rawId,
				JsonRpcErrorCode.serverNotInitialized,
				"Server not initialized"));
		}
		// notifications before initialize (except exit) are dropped
		continue;

	case LifecycleState.initializing:
	case LifecycleState.running:
		if (message.method == "exit")
		{
			info("Exit received");
			return state == LifecycleState.shutdownReceived ? 0 : 1;
		}
		if (message.method == "initialize")
		{
			// duplicate initialize is a protocol error
			sendJson(makeErrorResponse(message.rawId,
				JsonRpcErrorCode.invalidRequest,
				"Server already initialized"));
			continue;
		}
		{
			auto result = handleRequest(context, message.method, message.params);
			if (message.isRequest)
				sendHandlerResult(message.rawId, result);
			if (message.method == "shutdown")
				state = LifecycleState.shutdownReceived;
			else if (message.method == "initialized")
				state = LifecycleState.running;
		}
		continue;

	case LifecycleState.shutdownReceived:
		if (message.method == "exit")
		{
			info("Exit received");
			return 0;
		}
		if (message.isRequest)
		{
			// Per spec: requests after shutdown are rejected with InvalidRequest
			sendJson(makeErrorResponse(message.rawId,
				JsonRpcErrorCode.invalidRequest,
				"Server is shutting down"));
		}
		// notifications are dropped
		continue;

	case LifecycleState.exited:
		return 0;
	}
	}
}

/**
 * Sends a handler result as a JSON-RPC response.
 */
private void sendHandlerResult(JSONValue id, HandlerResult result)
{
	if (result.errorCode != 0)
		sendJson(makeErrorResponse(id, result.errorCode, result.errorMessage));
	else if (result.hasResult)
		sendJson(makeResponse(id, result.result));
	// notifications produce no response
}

/**
 * Sends a JSON value as a JSON-RPC message.
 */
private void sendJson(JSONValue json)
{
	writeMessageRaw(json.toString());
}

