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
	* Display of call tips for functions, constructors, and variables of function type
	* alias declarations
	* Public imports
	* Finding the declaration location of a symbol at the cursor
	* *import* statement completions
	* Display of documentation comments in function call tips
* Not working:
	* Automatic starting of the server by the client
	* UFCS
	* Autocompletion of declarations with template arguments
	* *auto* declarations
	* *alias this*
	* Determining the type of an enum member when no base type is specified, but the first member has an initialaizer
	* That one feature that you *REALLY* needed

#Setup
1. Install a recent D compiler. DCD is only tested with DMD 2.064.2
1. Run ```git submodule update --init``` after cloning this repository to grab the MessagePack and Datapacked libraries and the parser from DScanner.
1. run the ```build.sh``` script to build the client and server. (Or build.bat on Windows, or ```dub build --config=dcd-client --build=release``` and ```dub build --config=dcd-server --build=release``` in case of DUB usage)
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
completions depending on if the cursor was directly after a dot character or after
a left parethesis.

The file name is optional. If it is not specified, input will be read from *stdin*.

###Dot completion
When the first line of output is "identifiers", the editor should display a
completion list.
####Output format
A line containing the string "identifiers" followed by the completions that are
available, one per line. Each line consists of the completion name followed by a
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
* P - package name
* M - module name
* a - array
* A - associative array
* l - alias name
* t - template name
* T - mixin template name

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

####Note
DCD's output will start with "identifiers" when completing at a left paren
character if the keywords *pragma*, *scope*, *__traits*, *extern*, or *version*
were just before the paren.

###Parenthesis completion
When the first line of output is "calltips", the editor should display a function
call tip.
#####Output format
A line containing the string "calltips", followed by zero or more lines, each
containing a call tip for an overload of the given function.
#####Example output
	calltips
	ACSymbol findSymbolInCurrentScope(size_t cursorPosition, string name)

## Doc comment display
```dcd-client --doc -c 4298```
When run with the --doc or -d option, DCD will attempt to display documentation
comments associated with the symbol at the cursor position. In the case of
functions there can be more than one documentation comment associated with a
symbol. One doc comment will be printed per line. Newlines within the doc
comments will be replaced with "\n".
####Example output
	An example doc comment\nParams: a = first param\n    Returns: nothing
	An example doc comment\nParams: a = first param\n     b = second param\n    Returns: nothing

##Clear server's autocomplete cache
```dcd-client --clearCache```

##Add import search path
Import paths can be added to the server without restarting it. To accomplish
this, run the client with the -I option:

	dcd-client -Ipath/to/imports


##Find declaration of symbol at cursor
```dcd-client --symbolLocation -c 123```

The "--symbolLocation" or "-l" flags cause the client to instruct the server
to return the path to the file and the byte offset of the declaration of the
symbol at the given cursor position.

The output consists of the absolute path to the file followed by a tab character
followed by the byte offset, followed by a newline character. For example:

	/home/example/src/project/bar.d	3482

#Server
The server must be running for the DCD client to provide autocomplete information.
In future versions the client may start the server if it is not running, but for
now it must be started manually.

## Configuration Files
The server will attempt to read the file ```~/.config/dcd``` on Posix systems, or ```dcd.conf``` on Windows in the current working directory on startup.
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
