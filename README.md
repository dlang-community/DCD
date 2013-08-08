#Overview
The D Completion Daemon is an auto-complete program for the D programming language.

![Teaser](teaser.png "This is what the future looks like - Jayce, League of Legends")

#Status
* Working:
	* Autocompletion of properties of built-in types such as int, float, double, etc.
	* Autocompletion of __traits, scope, and extern arguments
	* Autocompletion of enums
* Crashes frequently
    * Autocompletion of class, struct, and interface instances.
* Not working:
	* Everything else

#Setup
Don't. This code is not ready for you to use yet. If you're going to ignore this
warning, be sure to run ```git submodule update --init``` after cloning this
repository to grab the MessagePack library.
