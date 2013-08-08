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

import msgpack;

import messages;
import autocomplete;
import modulecache;

int main(string[] args)
{
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

	// begin hack
	importPaths ~= "/home/alaran/src/dcd";
	importPaths ~= "/home/alaran/src/dscanner";
	importPaths ~= "/usr/include/d2/core";
	importPaths ~= "/usr/include/d2/phobos";
	importPaths ~= "/usr/include/d2/druntime/import";
	// end hack

	foreach (path; importPaths)
		ModuleCache.addImportPath(path);
	writeln("Import directories: ", ModuleCache.getImportPaths());

    auto socket = new TcpSocket(AddressFamily.INET);
    socket.blocking = true;
    socket.bind(new InternetAddress("127.0.0.1", port));
    socket.listen(0);
    scope (exit)
	{
		socket.shutdown(SocketShutdown.BOTH);
		socket.close();
	}
    ubyte[1024 * 1024 * 4] buffer = void; // 4 megabytes should be enough for anybody...
    while (true)
    {
        auto s = socket.accept();
        s.blocking = true;
        scope (exit)
		{
			s.shutdown(SocketShutdown.BOTH);
			s.close();
		}
        ptrdiff_t bytesReceived = s.receive(buffer);
        size_t messageLength;
        // bit magic!
        (cast(ubyte*) &messageLength)[0..8] = buffer[0..8];
        while (bytesReceived < messageLength + 8)
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
            writeln("Socket recieve failed");
            break;
        }

		AutocompleteRequest request;
		msgpack.unpack(buffer[8 .. bytesReceived], request);
		if (request.kind == RequestKind.addImport)
		{
			//ModuleCache.addImportPath();
		}
        else if (request.kind == RequestKind.clearCache)
		{
			writeln("Clearing cache.");
			ModuleCache.clear();
		}
		else if (request.kind == RequestKind.shutdown)
		{
			writeln("Shutting down.");
			break;
		}
		else
        {
            AutocompleteResponse response = complete(request, importPaths);
            ubyte[] responseBytes = msgpack.pack(response);
            assert(s.send(responseBytes) == responseBytes.length);
        }
    }
	return 0;
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
