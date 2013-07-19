module server;

import std.socket;
import std.stdio;
import std.getopt;

import msgpack;

import messages;
import autocomplete;

void main(string[] args)
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
    }

    auto socket = new TcpSocket(AddressFamily.INET);
    socket.blocking = true;
    socket.bind(new InternetAddress("127.0.0.1", port));
    socket.listen(0);
    scope (exit) socket.close();
    ubyte[1024 * 1024 * 4] buffer = void; // 4 megabytes should be enough for anybody...
    while (true)
    {
        auto s = socket.accept();
        s.blocking = true;
        scope (exit) s.close();
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
        else
        {
            AutocompleteRequest request;
            writeln("Unpacking ", bytesReceived, "/", buffer.length, " bytes into a request");
            msgpack.unpack(buffer[8 .. bytesReceived], request);
            AutocompleteResponse response = complete(request, importPaths);
            ubyte[] responseBytes = msgpack.pack(response);
            assert(s.send(responseBytes) == responseBytes.length);
        }
    }
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
