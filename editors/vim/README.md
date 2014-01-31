A plugin for using DCD with vim.

Tested on Linux (and a bit on Windows)

Installation
============

Vundle
------
1. Add `Bundle "Hackerpilot/DCD", {'rtp': 'editors/vim'}` to your vimrc.
2. `:BundleInstall`

Manual
------
Put the autoload and ftplugin folders in your vim runtime path.


Configuration
=============

Compile DCD and put both dcd-client and dcd-server in your path, or set the
global variable `g:dcd\_path` to where you put DCD.

You can set `g:dcd\_importPath` to an import path(or list of import paths) to
use when starting the server. You should do so for Phobos and DRuntime - since
DCD does not add them for you. On Linux it should be:

```vim
let g:dcd_importPath=['/usr/include/d','/usr/include/d/druntime/import']
```

On Windows you need to locate the root of your dmd installation (typically
`C:\D`). Phobos and DRuntime can be found within under `dmd2\src\phobos` and
`dmd2\src\druntime\import`, respectively. Example:
```vim
let g:dcd_importPath=['C:\D\dmd2\src\phobos','C:\D\dmd2\src\druntime\import']
```

Import paths are globbed with Vim's globbing function.

Usage
=====
When the filetype is D, use the `DCDstartServer` command to start the server
and the `DCDstopServer` command to stop the server. `DCDstartServer` can
receive import path(s) as arguments.

Use the `DCDaddPath` command to add a import path(s) to the server. Make sure you
escape spaces! Import paths are globbed with Vim's globbing function.

Use the `DCD` command to send arbitary commands to the server via the client.
The syntax is the same as with `dcd-client`, so you can use it without
arguments to print the help message.

Use `DCDclearCache` to clear the DCD server cache.

When the server is running, use `CTRL`+`x` `CTRL`+`o` in a D buffer to use DCD
completion.

When the server is running, use the `DCDdoc` to print the doc-string of symbol
under the cursor.

When the server is running, use the `DCDsymbolLocation` to print jump to the
declaration of the symbol under the cursor.

Conflicts
=========
This plugin conflicts with the DScanner plugin, as both use the `dcomplete`
autoload namespace and the `dcomplete#Complete` function - as per Vim's
conventions.

Configuration
=============

If you want to never add the closing paren in calltips completions, add this to you vimrc:
```vim
let g:dcd_neverAddClosingParen=1
```
