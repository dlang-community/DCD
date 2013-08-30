A plugin for using DCD with vim.

Tested on Linux(and a bit on Windows)

Installation and Configuration
==============================
Put the autoload and ftplugin folders in your vim runtime path.

Compile DCD and put both dcd-client and dcd-server in your path, or set the
global variable `g:dcd\_path` to where you put DCD.

You can set `g:dcd\_importPath` to an import path(or list of import paths) to
use when starting the server. You should do so for Phobos and DRuntime - since
DCD does not add them for you. On Linux it should be:

```vim
let g:dcd_importPath=['/usr/include/d','/usr/include/d/druntime/import']
```

On windows you need to look for the path in dmd's installation.

Import paths are globbed with Vim's globbing function.

Usage
===================
When the filetype is D, use the `DCDstartServer` command to start the server
and the `DCDstopServer` command to stop the server. `DCDstartServer` can
receive import path(s) as arguments.

Use the `DCDaddPath` command to add a import path(s) to the server. Make sure you
escape spaces! Import paths are globbed with Vim's globbing function.

Use the `DCD` command to send arbitary commands to the server via the client.
The syntax is the same as with `dcd-client`, so you can use it without
arguments to print the help message.

When the server is running, use `CTRL`+`x` `CTRL`+`o` in a D buffer to use DCD
completion.
