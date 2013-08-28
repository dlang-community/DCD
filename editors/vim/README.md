A plugin for using DCD with vim.

Tested on Linux

Installation and Configuration
==============================
Put the autoload and ftplugin folders in your vim runtime path.

Compile DCD and put both dcd-client and dcd-server in your path, or set the
global variable `g:dcd\_path` to where you put DCD.

Usage
===================
When the filetype is D, use the `DCDstartServer` command to start the server
and the `DCDstopServer` command to stop the server.

Use the `DCDaddPath` command to add an import path to the server. Make sure you
escape spaces!

Use the `DCD` command to send arbitary commands to the server via the client.
The syntax is the same as with `dcd-client`, so you can use it without
arguments to print the help message.

When the server is running, use `CTRL`+`x` `CTRL`+`o` to use DCD completion.
