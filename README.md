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
