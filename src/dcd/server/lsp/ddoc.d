module dcd.server.lsp.ddoc;

import std.algorithm : among, canFind, countUntil, endsWith, map, startsWith;
import std.array : appender, join;
import std.string : chompPrefix, indexOf, lineSplitter, strip, stripLeft;

/**
 * Converts a DDoc comment (with comment markers already stripped, as
 * libdparse's `Token.comment` provides) to markdown for LSP
 * `documentation` fields (hover, completion, signature help).
 *
 * Handles the constructs that actually appear in DCD's doc strings:
 * - standard sections (Params:, Returns:, See_Also:, Examples:, ...) as
 *   bold headings, Params entries as a list
 * - `---` code fences as ```d blocks
 * - inline macros: $(B x) -> **x**, $(I x) -> *x*, $(D x) / $(D_CODE x) ->
 *   `x`, $(REF x, a, b) / $(LREF x) -> `x`, $(LPAREN)/$(RPAREN) -> ( )
 * - unknown macros are stripped, keeping their content
 *
 * Unparseable input is returned unchanged (like serve-d's ddocToMarkdown).
 */
string ddocToMarkdown(string ddoc)
{
	if (!ddoc.length)
		return ddoc;

	string result;
	try
		result = convertSections(ddoc);
	catch (Exception e)
		return ddoc;
	return result;
}

private:

/// A section: everything before the first section heading is the summary.
struct Section
{
	string name;
	string[] lines;
}

Section[] splitSections(string ddoc)
{
	Section[] sections;
	Section current;

	foreach (line; ddoc.lineSplitter)
	{
		auto stripped = line.stripLeft;
		if (isSectionHeading(stripped))
		{
			if (current.lines.length || current.name.length)
				sections ~= current;
			current = Section(stripped[0 .. $ - 1], []);
		}
		else
			current.lines ~= line;
	}
	sections ~= current;
	return sections;
}

bool isSectionHeading(string line)
{
	// A section heading is a single word ending in ':' at the start of
	// the line, e.g. "Params:", "Returns:", "See_Also:". Code fences
	// ("---") and indented content are not headings.
	if (!line.endsWith(":"))
		return false;
	immutable head = line[0 .. $ - 1];
	if (!head.length)
		return false;
	foreach (c; head)
		if (!isIdentifierChar(c))
			return false;
	return true;
}

bool isIdentifierChar(dchar c)
{
	import std.ascii : isAlpha, isDigit;
	return isAlpha(c) || isDigit(c) || c == '_';
}

string convertSections(string ddoc)
{
	auto app = appender!string;
	foreach (i, section; splitSections(ddoc))
	{
		auto lines = section.lines;
		while (lines.length && !lines[$ - 1].strip.length)
			lines = lines[0 .. $ - 1];
		if (!lines.length && !section.name.length)
			continue;
		if (i)
			app.put('\n');
		auto content = convertMacros(lines.join("\n"));
		if (!section.name.length)
		{
			// summary: no heading
			app.put(content);
		}
		else if (section.name.among!("params", "Params"))
		{
			app.put("**Params**\n\n");
			foreach (name, desc; parseParams(lines))
				app.put("- `" ~ name ~ "` " ~ desc ~ "\n");
		}
		else
		{
			app.put("**" ~ section.name ~ "**\n\n");
			app.put(convertFences(content));
		}
		app.put('\n');
	}
	return app.data;
}

/**
 * Converts ddoc code fences (lines of exactly `---`) to markdown fences
 * tagged "d". Content between fences is left alone.
 */
string convertFences(string text)
{
	if (!canFind(text, "\n---"))
		return text;
	auto app = appender!string;
	bool inFence;
	foreach (line; text.lineSplitter)
	{
		if (line.strip == "---")
		{
			app.put(inFence ? "```\n" : "```d\n");
			inFence = !inFence;
		}
		else
			app.put(line ~ "\n");
	}
	return app.data;
}

/// Parses "name = description" entries of a Params section. The
/// description may span multiple indented lines.
string[string] parseParams(string[] lines)
{
	string[string] params;
	string currentName;
	string currentDesc;

	void flush()
	{
		if (currentName.length)
			params[currentName] = currentDesc.strip;
	}

	foreach (line; lines)
	{
		auto stripped = line.stripLeft;
		if (!stripped.length)
		{
			currentDesc ~= "\n";
			continue;
		}
		immutable eq = stripped.countUntil(" = ");
		if (eq > 0 && !stripped[0 .. eq].canFind(' '))
		{
			flush();
			currentName = stripped[0 .. eq];
			currentDesc = stripped[eq + 3 .. $];
		}
		else if (currentName.length)
			currentDesc ~= " " ~ stripped;
	}
	flush();
	return params;
}

/**
 * Expands ddoc inline macros. Only the common formatting ones are
 * translated; unknown macros keep their content verbatim.
 */
string convertMacros(string text)
{
	auto app = appender!string;
	size_t i;
	while (i < text.length)
	{
		if (text[i] != '$')
		{
			app.put(text[i]);
			i++;
			continue;
		}
		if (i + 1 >= text.length || text[i + 1] != '(')
		{
			app.put('$');
			i++;
			continue;
		}
		// find the matching close paren
		immutable open = i;
		size_t depth = 1;
		size_t j = i + 2;
		while (j < text.length && depth)
		{
			if (text[j] == '(')
				depth++;
			else if (text[j] == ')')
				depth--;
			j++;
		}
		if (depth)
		{
			// unbalanced: emit literally
			app.put('$');
			i++;
			continue;
		}
		immutable close = j - 1;
		// macro name: word chars between "$(" and the first space or ')'
		immutable nameEnd = nameEndIndex(text, open + 2, close);
		immutable name = text[open + 2 .. nameEnd];
		immutable argStart = nameEnd < close ? nameEnd + 1 : nameEnd;
		string arg = text[argStart .. close];

		switch (name)
		{
		case "B":
			app.put("**" ~ convertMacros(arg) ~ "**");
			break;
		case "I":
			app.put("*" ~ convertMacros(arg) ~ "*");
			break;
		case "U":
			app.put(convertMacros(arg));
			break;
		case "D", "D_CODE", "D_INLINECODE", "D_COMMENT", "D_STRING",
			"D_KEYWORD", "D_PSYMBOL", "D_PARAM":
			app.put("`" ~ convertMacros(arg) ~ "`");
			break;
		case "REF", "LREF", "GLINK":
			// $(REF name, module, ...) -> `name`
			app.put("`" ~ firstMacroArg(arg) ~ "`");
			break;
		case "LPAREN":
			app.put('(');
			break;
		case "RPAREN":
			app.put(')');
			break;
		case "DOLLAR":
			app.put('$');
			break;
		case "BACKTICK":
			app.put('`');
			break;
		case "P", "DDOC_SUMMARY", "DDOC_DESCRIPTION":
			app.put(convertMacros(arg));
			break;
		default:
			// unknown macro: keep content, drop the macro itself
			app.put(convertMacros(arg));
			break;
		}
		i = close + 1;
	}
	return app.data;
}

/// Index just past the macro name inside "$(NAME args)".
size_t nameEndIndex(string text, size_t start, size_t close)
{
	size_t j = start;
	while (j < close && isIdentifierChar(text[j]))
		j++;
	return j;
}

/// The first comma-separated argument of a macro, e.g. "add" of
/// "add, std, math".
string firstMacroArg(string args)
{
	immutable comma = args.indexOf(',');
	return comma == -1 ? args.strip : args[0 .. comma].strip;
}

unittest
{
	// summary only
	assert(ddocToMarkdown("Adds two ints.") == "Adds two ints.\n");

	// params section
	immutable params =
		"Does things.\n"
		~ "\n"
		~ "Params:\n"
		~ "    a = first\n"
		~ "    b = second\n";
	immutable expected =
		"Does things.\n"
		~ "\n"
		~ "**Params**\n"
		~ "\n"
		~ "- `a` first\n"
		~ "- `b` second\n"
		~ "\n";
	assert(ddocToMarkdown(params) == expected, ddocToMarkdown(params));

	// code fence
	immutable fence =
		"Examples:\n"
		~ "---\n"
		~ "auto s = add(1, 2);\n"
		~ "---\n";
	immutable expectedFence =
		"**Examples**\n"
		~ "\n"
		~ "```d\n"
		~ "auto s = add(1, 2);\n"
		~ "```\n"
		~ "\n";
	assert(ddocToMarkdown(fence) == expectedFence, ddocToMarkdown(fence));

	// inline macros
	assert(ddocToMarkdown("$(B bold) and $(I ital)") == "**bold** and *ital*\n");
	assert(ddocToMarkdown("$(D code)") == "`code`\n");
	assert(ddocToMarkdown("$(REF add, std, math)") == "`add`\n");
	assert(ddocToMarkdown("$(LPAREN)x$(RPAREN)") == "(x)\n");
	assert(ddocToMarkdown("$(UNKNOWN content)") == "content\n");

	// unbalanced macro is literal
	assert(ddocToMarkdown("costs $5") == "costs $5\n");

	// empty
	assert(ddocToMarkdown("") == "");
}
