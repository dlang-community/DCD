module dsymbol.coloredlogger;

import std.logger;
import std.stdio;
import std.concurrency;
import std.datetime;
import std.stdio;


import std.algorithm : map, filter, joiner;
import std.array : join, split;
import std.conv : to;
import std.format : format;
import std.functional : not;
import std.range : ElementType, empty, front, popFront;
import std.regex : ctRegex, Captures, replaceAll;
import std.string : toUpper;
import std.traits : EnumMembers;

version (unittest)
{
    import core.thread : Thread;
    import core.time : msecs;
    import std.conv : to;
    import std.process : environment;
    import std.stdio : writeln, write;
    import unit_threaded;
}
/// Available Colors
enum AnsiColor
{
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    lightGray = 37,
    defaultColor = 39,
    darkGray = 90,
    lightRed = 91,
    lightGreen = 92,
    lightYellow = 93,
    lightBlue = 94,
    lightMagenta = 95,
    lightCyan = 96,
    white = 97
}

/// Available Styles
enum Style
{
    bold = 1,
    dim = 2,
    underlined = 4,
    blink = 5,
    reverse = 7,
    hidden = 8
}

/// Internal structure to style a string
struct StyledString
{
    private string unformatted;
    private int[] befores;
    private int[] afters;
    /// Create a styled string
    public this(string unformatted)
    {
        this.unformatted = unformatted;
    }

    private StyledString addPair(int before, int after)
    {
        befores ~= before;
        afters ~= after;
        return this;
    }

    StyledString setForeground(int color)
    {
        return addPair(color, 0);
    }

    StyledString setBackground(int color)
    {
        return addPair(color + 10, 0);
    }

    /// Add styling to a string
    StyledString addStyle(int style)
    {
        return addPair(style, 0);
    }

    string toString() const @safe
    {
        auto prefix = befores.map!(a => "\033[%dm".format(a)).join("");
        auto suffix = afters.map!(a => "\033[%dm".format(a)).join("");
        return "%s%s%s".format(prefix, unformatted, suffix);
    }

    /// Concatenate with another string
    string opBinary(string op : "~")(string rhs) @safe
    {
        return toString ~ rhs;
    }
}

/// Truecolor string
struct RGBString
{
    private string unformatted;
    /// Colorinformation
    struct RGB
    {
        /// Red component 0..256
        ubyte r;
        /// Green component 0..256
        ubyte g;
        /// Blue component 0..256
        ubyte b;
    }

    private RGB* foreground;
    private RGB* background;
    /// Create RGB String
    this(string unformatted)
    {
        this.unformatted = unformatted;
    }

    /// Set color
    auto rgb(ubyte r, ubyte g, ubyte b)
    {
        this.foreground = new RGB(r, g, b);
        return this;
    }

    /// Set background color
    auto onRgb(ubyte r, ubyte g, ubyte b)
    {
        this.background = new RGB(r, g, b);
        return this;
    }

    string toString() @safe
    {
        auto res = "";
        if (foreground != null)
        {
            res = "\033[38;2;%s;%s;%sm".format(foreground.r, foreground.g, foreground.b) ~ res;
        }
        if (background != null)
        {
            res = "\033[48;2;%s;%s;%sm".format(background.r, background.g, background.b) ~ res;
        }
        res ~= unformatted;
        if (foreground != null || background != null)
        {
            res ~= "\033[0m";
        }
        return res;
    }
}

/// Convinient helper function
string rgb(string s, ubyte r, ubyte g, ubyte b)
{
    return RGBString(s).rgb(r, g, b).toString;
}

/// Convinient helper function
string onRgb(string s, ubyte r, ubyte g, ubyte b)
{
    return RGBString(s).onRgb(r, g, b).toString;
}

@system @("rgb") unittest
{
    import std.experimental.color : RGBA8, convertColor;
    import std.experimental.color.hsx : HSV;

    writeln("red: ", "r".rgb(255, 0, 0).onRgb(0, 255, 0));
    writeln("green: ", "g".rgb(0, 255, 0).onRgb(0, 0, 255));
    writeln("blue: ", "b".rgb(0, 0, 255).onRgb(255, 0, 0));
    writeln("mixed: ", ("withoutColor" ~ "red".red.to!string ~ "withoutColor").bold);
    for (int r = 0; r <= 255; r += 10)
    {
        for (int g = 0; g <= 255; g += 3)
        {
            write(" ".onRgb(cast(ubyte) r, cast(ubyte) g, cast(ubyte)(255 - r)));
        }
        writeln;
    }

    int delay = environment.get("DELAY", "0").to!int;
    for (int j = 0; j < 255; j += 1)
    {
        for (int i = 0; i < 255; i += 3)
        {
            auto c = HSV!ubyte(cast(ubyte)(i - j), 0xff, 0xff);
            auto rgb = convertColor!RGBA8(c).tristimulus;
            write(" ".onRgb(rgb[0].value, rgb[1].value, rgb[2].value));
        }
        Thread.sleep(delay.msecs);
        write("\r");
    }
    writeln;
}

@system @("styledstring") unittest
{
    foreach (immutable color; [EnumMembers!AnsiColor])
    {
        auto colorName = "%s".format(color);
        writeln(StyledString(colorName).setForeground(color));
    }
    foreach (immutable color; [EnumMembers!AnsiColor])
    {
        auto colorName = "bg%s".format(color);
        writeln(StyledString(colorName).setBackground(color));
    }
    foreach (immutable style; [EnumMembers!Style])
    {
        auto styleName = "%s".format(style);
        writeln(StyledString(styleName).addStyle(style));
    }

    writeln("boldUnderlined".bold.underlined);
    writeln("redOnGreenReverse".red.onGreen.reverse);
}

@system @("styledstring ~") unittest
{
    ("test".red ~ "blub").should == "\033[31mtest\033[0mblub";
}

/// Create `color` and `onColor` functions for all enum members. e.g. "abc".green.onRed
auto colorMixin(T)()
{
    string res = "";
    foreach (immutable color; [EnumMembers!T])
    {
        auto t = typeof(T.init).stringof;
        auto c = "%s".format(color);
        res ~= "auto %1$s(string s) { return StyledString(s).setForeground(%2$s.%1$s); }\n".format(c,
                t);
        res ~= "auto %1$s(StyledString s) { return s.setForeground(%2$s.%1$s); }\n".format(c, t);
        string name = c[0 .. 1].toUpper ~ c[1 .. $];
        res ~= "auto on%3$s(string s) { return StyledString(s).setBackground(%2$s.%1$s); }\n".format(c,
                t, name);
        res ~= "auto on%3$s(StyledString s) { return s.setBackground(%2$s.%1$s); }\n".format(c,
                t, name);
    }
    return res;
}

/// Create `style` functions for all enum mebers, e.g. "abc".bold
auto styleMixin(T)()
{
    string res = "";
    foreach (immutable style; [EnumMembers!T])
    {
        auto t = typeof(T.init).stringof;
        auto s = "%s".format(style);
        res ~= "auto %1$s(string s) { return StyledString(s).addStyle(%2$s.%1$s); }\n".format(s, t);
        res ~= "auto %1$s(StyledString s) { return s.addStyle(%2$s.%1$s); }\n".format(s, t);
    }
    return res;
}

mixin(colorMixin!AnsiColor);
mixin(styleMixin!Style);

@system @("api") unittest
{
    "redOnGreen".red.onGreen.writeln;
    "redOnYellowBoldUnderlined".red.onYellow.bold.underlined.writeln;
    "bold".bold.writeln;
    "test".writeln;
}

/// Calculate length of string excluding all formatting escapes
ulong unformattedLength(string s)
{
    enum State
    {
        NORMAL,
        ESCAPED,
    }

    auto state = State.NORMAL;
    ulong count = 0;
    foreach (c; s)
    {
        switch (state)
        {
        case State.NORMAL:
            if (c == 0x1b)
            {
                state = State.ESCAPED;
            }
            else
            {
                count++;
            }
            break;
        case State.ESCAPED:
            if (c == 'm')
            {
                state = State.NORMAL;
            }
            break;
        default:
            throw new Exception("Illegal state");
        }
    }
    return count;
}

/++ Range to work with ansi escapes. The ESC[ parts and m must be
 + already removed and the numbers need to be converted to uints.
 + See https://en.wikipedia.org/wiki/ANSI_escape_code
 +/
auto tokenize(Range)(Range parts)
{
    struct TokenizeResult(Range)
    {
        Range parts;
        ElementType!(Range)[] next;
        this(Range parts)
        {
            this.parts = parts;
            tokenizeNext();
        }

        private void tokenizeNext()
        {
            next = [];
            if (parts.empty)
            {
                return;
            }
            switch (parts.front)
            {
            case 38:
            case 48:
                next ~= 38;
                parts.popFront;
                switch (parts.front)
                {
                case 2:
                    next ~= 2;
                    parts.popFront;
                    next ~= parts.front;
                    parts.popFront;
                    next ~= parts.front;
                    parts.popFront;
                    next ~= parts.front;
                    parts.popFront;
                    break;
                case 5:
                    next ~= 5;
                    parts.popFront;
                    next ~= parts.front;
                    parts.popFront;
                    break;
                default:
                    throw new Exception("Only [38,48];[2,5] are supported but got %s;%s".format(next[0],
                            parts.front));
                }
                break;
            case 0: .. case 37:
            case 39: .. case 47:
            case 49:
            case 51:
                    .. case 55:
            case 60: .. case 65:
            case 90: .. case 97:
            case 100: .. case 107:
                next ~= parts.front;
                parts.popFront;
                break;
            default:
                throw new Exception("Only colors are supported");
            }
        }

        auto front()
        {
            return next;
        }

        bool empty()
        {
            return next == null;
        }

        void popFront()
        {
            tokenizeNext();
        }
    }

    return TokenizeResult!(Range)(parts);
}

@system @("ansi tokenizer") unittest
{
    [38, 5, 2, 38, 2, 1, 2, 3, 36, 1, 2, 3, 4].tokenize.should == ([
        [38, 5, 2], [38, 2, 1, 2, 3], [36], [1], [2], [3], [4]
    ]);
}

/++ Remove classes of ansi escapes from a styled string.
 +/
string filterAnsiEscapes(alias predicate)(string s)
{
    string withFilters(Captures!string c)
    {
        auto parts = c[1].split(";").map!(a => a.to!uint)
            .tokenize
            .filter!(p => predicate(p));
        if (parts.empty)
        {
            return "";
        }
        else
        {
            return "\033[" ~ parts.joiner.map!(a => "%d".format(a)).join(";") ~ "m";
        }
    }

    alias r = ctRegex!"\033\\[(.*?)m";
    return s.replaceAll!(withFilters)(r);
}

/// Predicate to select foreground color ansi escapes
bool foregroundColor(uint[] token)
{
    return token[0] >= 30 && token[0] <= 38;
}

/// Predicate to select background color ansi escapes
bool backgroundColor(uint[] token)
{
    return token[0] >= 40 && token[0] <= 48;
}

/// Predicate to select style ansi escapes
bool style(uint[] token)
{
    return token[0] >= 1 && token[0] <= 29;
}

/// Predicate select nothing
bool none(uint[])
{
    return false;
}

/// Predicate to select all
bool all(uint[])
{
    return true;
}

@system @("configurable strip") unittest
{
    import unit_threaded;
    import std.functional : not;

    "test".red.onGreen.bold.toString.filterAnsiEscapes!(foregroundColor).should == "\033[31mtest";
    "test".red.onGreen.bold.toString.filterAnsiEscapes!(not!foregroundColor)
        .should == "\033[42m\033[1mtest\033[0m\033[0m\033[0m";
    "test".red.onGreen.bold.toString.filterAnsiEscapes!(style).should == "\033[1mtest";
    "test".red.onGreen.bold.toString.filterAnsiEscapes!(none).should == "test";
    "test".red.onGreen.bold.toString.filterAnsiEscapes!(all)
        .should == "\033[31m\033[42m\033[1mtest\033[0m\033[0m\033[0m";
    "test".red.onGreen.bold.toString.filterAnsiEscapes!(backgroundColor).should == "\033[42mtest";
}

/// Add fillChar to the right of the string until width is reached
auto leftJustifyFormattedString(string s, ulong width, dchar fillChar = ' ')
{
    auto res = s;
    const currentWidth = s.unformattedLength;
    for (long i = currentWidth; i < width; ++i)
    {
        res ~= fillChar;
    }
    return res;
}

@system @("leftJustifyFormattedString") unittest
{
    import unit_threaded;

    "test".red.toString.leftJustifyFormattedString(10).should == "\033[31mtest\033[0m      ";
}

/// Add fillChar to the left of the string until width is reached
auto rightJustifyFormattedString(string s, ulong width, char fillChar = ' ')
{
    auto res = s;
    const currentWidth = s.unformattedLength;
    for (long i = currentWidth; i < width; ++i)
    {
        res = fillChar ~ res;
    }
    return res;
}

@system @("rightJustifyFormattedString") unittest
{
    "test".red.toString.rightJustifyFormattedString(10).should == ("      \033[31mtest\033[0m");
}

/// Force a style on possible preformatted text
auto forceStyle(string text, Style style) {
    return "\033[%d".format(style.to!int) ~ "m" ~ text.split("\033[0m").join("\033[0;%d".format(style.to!int) ~"m") ~ "\033[0m";
}

@("forceStyle") unittest
{
    auto splitt = "1es2eses3".split("es").filter!(not!(empty));
    splitt.should == ["1", "2", "3"];
    string s = "noformatting%snoformatting".format("red".red).forceStyle(Style.reverse);
    writeln(s);
    s.should == "\033[7mnoformatting\033[31mred\033[0;7mnoformatting\033[0m";
}
