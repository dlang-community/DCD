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
