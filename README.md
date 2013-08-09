#Overview
The D Completion Daemon is an auto-complete program for the D programming language.

![Teaser](teaser.png "This is what the future looks like - Jayce, League of Legends")

#Status
*This program is still in an alpha state.*

* Working:
	* Autocompletion of properties of built-in types such as int, float, double, etc.
	* Autocompletion of __traits, scope, and extern arguments
	* Autocompletion of enums
	* Autocompletion of class, struct, and interface instances.
	* Display of call tips (but only for the first overload)
* Not working:
	* UFCS
	* Templates
	* *auto* declarations
	* Operator overloading (opIndex, opSlice, etc) when autocompleting
	* Instances of enum types resolve to the enum itself instead of the enum base type
	* Function parameters do not appear in the scope of the function body
	* Public imports
	* That one feature that you *REALLY* needed

#Setup
1. Run ```git submodule update --init``` after cloning this repository to grab the MessagePack library.
1. The build script assumes that the DScanner project is cloned into a sibling folder. (i.e. "../dscanner" should exist).
1. Modify the server.d file because several import paths are currently hard-coded. (See also: the warning at the beginnig that this is alpha-quality)
1. Configure your text editor to call the dcd-client program
1. Start the dcd-server program before editing code.

#Client usage

##Get autocomplete information
The primary use case of the client is to query the server for autocomplete information.
To do this, provide the client with the file that the user is editing along with the
cursor position (in bytes).
```dcd-client -c123 sourcefile.d```

This will cause the client to print a listing of completions to *stdout*.
The client will print either a listing of function call tips, or a listing of of
completions depending on if the cursor was directly after a dot character or a
left parethesis.

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

##Specify server port
```dcd-client -p4242```

##Add import search path
```dcd-client -Ipath/to/imports```

##Shut down the server
```dcd-client --shutdown```

#Server usage
## Import directories
The ```-I``` option allows you to specify directories to be searched for modules
## Port number
The ```--port``` or ```-p``` option lets you specify the port number that the server will listen on
