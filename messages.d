/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2013 Brian Schott
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module messages;

/**
 * Identifies the kind of the item in an identifier completion list
 */
enum CompletionKind : char
{
    /// class names
    className = 'c',

    /// interface names
    interfaceName = 'i',

    /// structure names
    structName = 's',

    /// variable name
    variableName = 'v',

    /// member variable
    memberVariableName = 'm',

    /// keyword, built-in version, scope statement
    keyword = 'k',

    /// function or method
    functionName = 'f',

    /// enum name
    enumName = 'g',

    /// package name
    packageName = 'P',

    // module name
    moduleName = 'M'
}

/**
 * The type of completion list being returned
 */
enum CompletionType : string
{
    /**
     * The completion list contains a listing of identifier/kind pairs.
     */
    identifiers = "identifiers",

    /**
     * The auto-completion list consists of a listing of functions and their
     * parameters.
     */
    calltips = "calltips"
}

/**
 * Autocompletion request message
 */
struct AutocompleteRequest
{
    /**
     * File name used for error reporting
     */
    string fileName;

    /**
     * Paths to be searched for import files
     */
    string[] importPaths;

    /**
     * The source code to auto complete
     */
    ubyte[] sourceCode;

    /**
     * The cursor position
     */
    int cursorPosition;
}

/**
 * Autocompletion response message
 */
struct AutocompleteResponse
{
    /**
     * The autocompletion type. (Parameters or identifier)
     */
    string completionType;

    /**
     * The completions
     */
    string[] completions;

    /**
     * The kinds of the items in the completions array. Will be empty if the
     * completion type is a function argument list.
     */
    char[] completionKinds;
}
