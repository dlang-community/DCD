module client;

import std.socket;
import std.stdio;
import std.getopt;
import std.array;

import msgpack;
import messages;

int main(string[] args)
{
    int cursorPos = -1;
    string[] importPaths;
    ushort port = 9090;
    bool help;

    try
    {
        getopt(args, "cursorPos|c", &cursorPos, "I", &importPaths,
            "port|p", &port, "help|h", &help);
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

    // cursor position is a required argument
    if (cursorPos == -1)
    {
        printHelp(args[0]);
        return 1;
    }

    // Read in the source
    bool usingStdin = args.length <= 1;
    string fileName = usingStdin ? "stdin" : args[1];
    File f = usingStdin ? stdin : File(args[1]);
    ubyte[] sourceCode = usingStdin ? cast(ubyte[]) [] : uninitializedArray!(ubyte[])(f.size);
    f.rawRead(sourceCode);

    // Create message
    AutocompleteRequest request;
    request.fileName = fileName;
    request.importPaths = importPaths;
    request.sourceCode = sourceCode;
    request.cursorPosition = cursorPos;
    ubyte[] message = msgpack.pack(request);

    // Send message to server
    auto socket = new TcpSocket(AddressFamily.INET);
    scope (exit) socket.close();
    socket.connect(new InternetAddress("127.0.0.1", port));
    socket.blocking = true;
    stderr.writeln("Sending ", message.length, " bytes");
    auto bytesSent = socket.send(message);
    stderr.writeln(bytesSent, " bytes sent");

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
    stderr.writeln("completed");
    return 0;
}

void printHelp(string programName)
{
    writefln(
`
    Usage: %1$s --cursorPos NUMBER [options] [FILENAME]
       or: %1$s -cNUMBER [options] [FILENAME]

    A file name is optional. If it is given, autocomplete information will be
    given for the file specified. If it is missing, input will be read from
    stdin instead.

    Source code is assumed to be UTF-8 encoded.

Mandatory Arguments:
    --cursorPos | -c position
        Provides auto-completion at the given cursor position. The cursor
        position is measured in bytes from the beginning of the source code.

Options:
    --help | -h
        Displays this help message

    -IPATH
        Includes PATH in the listing of paths that are searched for file imports

    --port PORTNUMBER | -pPORTNUMBER
        Uses PORTNUMBER to communicate with the server instead of the default
        port 9091.`, programName);
}
