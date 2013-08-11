#Overview
The D Completion Daemon is an auto-complete program for the D programming language.

![Teaser](teaser.png "This is what the future looks like - Jayce, League of Legends")

DCD consists of a client and a server. The client (dcd-client) is used by a text editor script or from the command line.
The server (dcd-server) is responsible for caching imported files, calculating autocomplete information, and sending it
back to the client.

#Status
*This program is still in an alpha state.*

* Working:
	* Autocompletion of properties of built-in types such as int, float, double, etc.
	* Autocompletion of __traits, scope, and extern arguments
	* Autocompletion of enums
	* Autocompletion of class, struct, and interface instances.
	* Display of call tips for functions and constructors
* Not working:
	* Automatic starting of the server by the client
	* Windows support (I don't know that it won't work, but this program is not tested on Windows yet)
	* UFCS
	* Templated declarations
	* *auto* declarations
	* alias declarations
	* Determining the type of an enum member when no base type is specified, but the first member has an initialaizer
	* Public imports
	* That one feature that you *REALLY* needed

#Setup
1. Run ```git submodule update --init``` after cloning this repository to grab the MessagePack library.
1. The build script assumes that the DScanner project is cloned into a sibling folder. (i.e. "../dscanner" should exist)
1. Configure your text editor to call the dcd-client program. See the *editors* folder for directions on configuring your specific editor.
1. Start the dcd-server program before editing code.

#Client

##Get autocomplete information
The primary use case of the client is to query the server for autocomplete information.
To do this, provide the client with the file that the user is editing along with the
cursor position (in bytes).

```dcd-client -c123 sourcefile.d```

This will cause the client to print a listing of completions to *stdout*.
The client will print either a listing of function call tips, or a listing of of
completions depending on if the cursor was directly after a dot character or a
left parethesis.

The file name is optional. If it is not specified, input will be read from *stdin*.

###Dot completion
When the first line of output is "identifiers", the editor should display a
completion list.
####Output format
A line containing the string "identifiers" followed by the completions that are
available, one per line. Each line consists of the completion name folled by a
tab character, followed by a completion kind
#####Completion kinds
* c - class name
* i - interface name
* s - struct name
* u - union name
* v - variable name
* m - member variable name
* k - keyword, built-in version, scope statement
* f - function or method
* g - enum name
* e - enum member
* p - package name
* M - module name

####Example output
	identifiers
	parts	v
	name	v
	location	v
	qualifier	v
	kind	v
	type	v
	resolvedType	v
	calltip	v
	getPartByName	f

####Parenthesis completion
When the first line of output is "calltips", the editor should display a function
call tip.
#####Output format
A line containing the string "calltips", followed by zero or more lines, each
containing a call tip for an overload of the given function.
#####Example output
	calltips
	ACSymbol findSymbolInCurrentScope(size_t cursorPosition, string name)

##Clear server's autocomplete cache
```dcd-client --clearCache```

##Add import search path
Import paths can be added to the server without restarting it. To accomplish
this, run the client with the -I option:

	dcd-client -Ipath/to/imports

#Server
The server must be running for the DCD client to provide autocomplete information.
In future versions the client may start the server if it is not running, but for
now it must be started manually.

## Configuration Files
The server will attempt to read the file ```~/.config/dcd``` on startup.
If it exists, each line of the file is interpreted as a path that should be
searched when looking for module imports.

##Shut down the server
The server can be shut down by running the client with the correct option:

	dcd-client --shutdown

## Import directories
Import directories can be specified on the command line at startup:

	dcd-server -I/home/user/code/one -I/home/user/code/two

## Port number
The ```--port``` or ```-p``` option lets you specify the port number that the server will listen on.
