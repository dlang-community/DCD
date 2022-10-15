module dcd.server.autocomplete.calltip_utils;
import std.string;
import std.regex;
import std.range : empty;
import std.experimental.logger;
import std.algorithm : canFind;

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
