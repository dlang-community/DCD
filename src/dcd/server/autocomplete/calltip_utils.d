module dcd.server.autocomplete.calltip_utils;

import std.string;
import std.regex;
import std.range : empty;
import std.experimental.logger;
import std.algorithm : canFind;

/** 
 *   Extracting the first argument type
 * which isn't lazy, return, scope etc
 * Params:
 *   text = the string we want to extract from
 * Returns: first type in the text
 */
string extractFirstArgType(string text)
{
    // Then match the first word that isn't lazy return scope ... etc.
    auto firstWordRegex = regex(`(?!lazy|return|scope|in|out|ref|const|immutable\b)\b\w+`);

    auto matchFirstType = matchFirst(text, firstWordRegex);
    string firstArgument = matchFirstType.captures.back;
    return firstArgument.empty ? "" : firstArgument;

}

/** 
 * 
 * Params:
 *   callTip = the symbols calltip
 * Returns: the first argument type of the calltip 
 */
string getFirstArgumentOfFunction(string callTip)
{
    auto splitParentheses = callTip.split('(');

    // First match all inside the parentheses
    auto insideParenthesesRegex = regex(`\((.*\))`);
    auto match = matchFirst(callTip, insideParenthesesRegex);
    string insideParentheses = match.captures.back;

    if (insideParentheses.empty)
    {
        return "";
    }

    return extractFirstArgType(insideParentheses);

}

string removeFirstArgumentOfFunction(string callTip)
{
    auto parentheseSplit = callTip.split('(');
    // has only one argument
    if (!callTip.canFind(','))
    {
        return parentheseSplit[0] ~ "()";
    }
    auto commaSplit = parentheseSplit[1].split(',');
    string newCallTip = callTip.replace((commaSplit[0] ~ ", "), "");
    return newCallTip;

}

unittest
{
    auto result = getFirstArgumentOfFunction("void fooFunction(ref const(Foo) bar)");
    assert(result, "Foo");
}

unittest
{
    auto result = getFirstArgumentOfFunction("void fooFunction(Foo foo, string message)");
    assert(result, "Foo");
}

unittest
{
    auto result = getFirstArgumentOfFunction("void fooFunction(ref immutable(Foo) bar)");
    assert(result, "Foo");
}

unittest
{
    auto result = getFirstArgumentOfFunction("void fooFunction(const(immutable(Foo)) foo)");
    assert(result, "Foo");
}

unittest
{
    auto result = removeFirstArgumentOfFunction("void fooFunction(const(immutable(Foo)) foo)");
    assert(result, "void fooFunction()");
}

unittest
{
    auto result = removeFirstArgumentOfFunction(
        "void fooFunction(const(immutable(Foo)) foo), string message");
    assert(result, "void fooFunction(string message)");
}

unittest
{
    auto result = removeFirstArgumentOfFunction(
        "void fooFunction(const(immutable(Foo)) foo), string message, ref int age");
    assert(result, "void fooFunction(string message, ref int age)");
}
