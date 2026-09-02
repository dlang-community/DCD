/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2014 Brian Schott
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

module dcd.server.lsp.protocol;

import std.algorithm;
import std.array;
import std.conv;
import std.json;
import std.string;

import dsymbol.symbol : CompletionKind;

/**
 * A position in a text document expressed as zero-based line and character.
 *
 * Characters are UTF-8 code unit offsets within the line when the negotiated
 * position encoding is UTF-8 (the default for this server), or UTF-16 code
 * units otherwise.
 */
struct Position
{
	size_t line;
	size_t character;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		obj["line"] = JSONValue(line);
		obj["character"] = JSONValue(character);
		return obj;
	}

	static Position fromJson(JSONValue json)
	{
		Position p;
		p.line = json["line"].integer.to!size_t;
		p.character = json["character"].integer.to!size_t;
		return p;
	}
}

/**
 * A range in a text document expressed as start and end positions.
 */
struct Range
{
	Position start;
	Position end;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		obj["start"] = start.toJson();
		obj["end"] = end.toJson();
		return obj;
	}

	static Range fromJson(JSONValue json)
	{
		Range r;
		r.start = Position.fromJson(json["start"]);
		r.end = Position.fromJson(json["end"]);
		return r;
	}
}

/**
 * Represents a location inside a resource, such as a line inside a text
 * document.
 */
struct Location
{
	string uri;
	Range range;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		obj["uri"] = JSONValue(uri);
		obj["range"] = range.toJson();
		return obj;
	}
}

/**
 * The kind of a completion entry.
 */
enum CompletionItemKind : int
{
	text = 1,
	method = 2,
	function_ = 3,
	constructor = 4,
	field = 5,
	variable = 6,
	class_ = 7,
	interface_ = 8,
	module_ = 9,
	property = 10,
	unit = 11,
	value = 12,
	enum_ = 13,
	keyword = 14,
	snippet = 15,
	color = 16,
	file = 17,
	reference = 18,
	folder = 19,
	enumMember = 20,
	struct_ = 22,
	event = 23,
	operator = 24,
	typeParameter = 25,
}

/**
 * Maps a DCD `CompletionKind` to an LSP `CompletionItemKind`.
 */
CompletionItemKind toCompletionItemKind(CompletionKind kind)
{
	final switch (kind)
	{
		case CompletionKind.dummy:
			return CompletionItemKind.text;
		case CompletionKind.importSymbol:
			return CompletionItemKind.module_;
		case CompletionKind.withSymbol:
			return CompletionItemKind.text;
		case CompletionKind.className:
			return CompletionItemKind.class_;
		case CompletionKind.interfaceName:
			return CompletionItemKind.interface_;
		case CompletionKind.structName:
			return CompletionItemKind.struct_;
		case CompletionKind.unionName:
			return CompletionItemKind.struct_;
		case CompletionKind.variableName:
			return CompletionItemKind.variable;
		case CompletionKind.memberVariableName:
			return CompletionItemKind.field;
		case CompletionKind.keyword:
			return CompletionItemKind.keyword;
		case CompletionKind.functionName:
			return CompletionItemKind.function_;
		case CompletionKind.ufcsName:
		// Extension-method style: VS Code has no dedicated "extension"
		// icon, but the method cube (vs the plain ƒ) gives UFCS functions a
		// distinct look, like C# extension methods in VS Code.
		return CompletionItemKind.method;
		case CompletionKind.enumName:
			return CompletionItemKind.enum_;
		case CompletionKind.enumMember:
			return CompletionItemKind.enumMember;
		case CompletionKind.packageName:
			return CompletionItemKind.module_;
		case CompletionKind.moduleName:
			return CompletionItemKind.module_;
		case CompletionKind.aliasName:
			return CompletionItemKind.reference;
		case CompletionKind.templateName:
			return CompletionItemKind.typeParameter;
		case CompletionKind.mixinTemplateName:
			return CompletionItemKind.typeParameter;
		case CompletionKind.variadicTmpParam:
			return CompletionItemKind.typeParameter;
		case CompletionKind.typeTmpParam:
			return CompletionItemKind.typeParameter;
	}
}

/**
 * How the server and client should synchronize document changes.
 */
enum TextDocumentSyncKind : int
{
	none = 0,
	full = 1,
	incremental = 2,
}

/**
 * A completion item to present in the editor.
 */
struct CompletionItem
{
	string label;
	string detail;
	string documentation;
	CompletionItemKind kind;
	/// LSP 3.17 `labelDetails.detail`: rendered right after the label (grayed
	/// in VS Code). Carries the parameter list of functions.
	string labelDetail;
	/// LSP 3.17 `labelDetails.description`: rendered on the right side of
	/// every row (grayed). Carries the "ufcs" marker for UFCS functions.
	string labelDescription;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		obj["label"] = JSONValue(label);
		obj["kind"] = JSONValue(cast(int) kind);
		if (detail.length)
			obj["detail"] = JSONValue(detail);
		if (documentation.length)
			obj["documentation"] = JSONValue(documentation);
		if (labelDetail.length || labelDescription.length)
		{
			JSONValue labelDetails = parseJSON(`{}`);
			if (labelDetail.length)
				labelDetails["detail"] = JSONValue(labelDetail);
			if (labelDescription.length)
				labelDetails["description"] = JSONValue(labelDescription);
			obj["labelDetails"] = labelDetails;
		}
		return obj;
	}
}

/**
 * Represents a collection of completion items to be presented in the editor.
 */
struct CompletionList
{
	bool isIncomplete;
	CompletionItem[] items;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		obj["isIncomplete"] = JSONValue(isIncomplete);
		JSONValue[] itemArray;
		foreach (item; items)
			itemArray ~= item.toJson();
		obj["items"] = JSONValue(itemArray);
		return obj;
	}
}

/**
 * The result of a hover request.
 */
struct Hover
{
	string contents;
	Range range;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		JSONValue markup = parseJSON(`{}`);
		markup["kind"] = JSONValue("markdown");
		markup["value"] = JSONValue(contents);
		obj["contents"] = markup;
		if (range.start.line != 0 || range.start.character != 0
			|| range.end.line != 0 || range.end.character != 0)
			obj["range"] = range.toJson();
		return obj;
	}
}

/**
 * A parameter of a callable signature.
 *
 * The label is expressed as `[labelStart, labelEnd)` offsets into the
 * enclosing signature's label (LSP `labelOffsetSupport`), so the client can
 * highlight the active parameter inside the signature string.
 */
struct ParameterInformation
{
	size_t labelStart;
	size_t labelEnd;
	string documentation;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		JSONValue[] offsets;
		offsets ~= JSONValue(cast(long) labelStart);
		offsets ~= JSONValue(cast(long) labelEnd);
		obj["label"] = JSONValue(offsets);
		if (documentation.length)
			obj["documentation"] = JSONValue(documentation);
		return obj;
	}
}

/**
 * Represents the signature of a callable.
 */
struct SignatureInformation
{
	string label;
	string documentation;
	ParameterInformation[] parameters;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		obj["label"] = JSONValue(label);
		if (documentation.length)
			obj["documentation"] = JSONValue(documentation);
		if (parameters.length)
		{
			JSONValue[] params;
			foreach (param; parameters)
				params ~= param.toJson();
			obj["parameters"] = JSONValue(params);
		}
		return obj;
	}
}

/**
 * Signature help represents the signature of something callable.
 */
struct SignatureHelp
{
	SignatureInformation[] signatures;
	size_t activeSignature;
	size_t activeParameter;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		JSONValue[] sigs;
		foreach (sig; signatures)
			sigs ~= sig.toJson();
		obj["signatures"] = JSONValue(sigs);
		obj["activeSignature"] = JSONValue(activeSignature);
		obj["activeParameter"] = JSONValue(activeParameter);
		return obj;
	}
}

/**
 * An inlay hint.
 */
struct InlayHint
{
	Position position;
	string label;
	string tooltip;
	/// LSP InlayHintKind: 1 = Type, 2 = Parameter
	int kind;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		obj["position"] = position.toJson();
		obj["label"] = JSONValue(label);
		obj["kind"] = JSONValue(kind);
		if (tooltip.length)
			obj["tooltip"] = JSONValue(tooltip);
		return obj;
	}
}

/**
 * A textual edit applicable to a document.
 */
struct TextEdit
{
	Range range;
	string newText;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		obj["range"] = range.toJson();
		obj["newText"] = JSONValue(newText);
		return obj;
	}
}

/**
 * A workspace or document diagnostic.
 */
struct Diagnostic
{
	Range range;
	string message;
	/// LSP DiagnosticSeverity: 1 = Error, 2 = Warning, 3 = Information, 4 = Hint
	int severity;

	JSONValue toJson() const
	 {
		JSONValue obj = parseJSON(`{}`);
		obj["range"] = range.toJson();
		obj["message"] = JSONValue(message);
		if (severity)
			obj["severity"] = JSONValue(severity);
		return obj;
	}
}

/**
 * A document symbol for hierarchical outline views.
 */
struct DocumentSymbol
{
	string name;
	string detail;
	CompletionItemKind kind;
	Range range;
	Range selectionRange;
	DocumentSymbol[] children;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		obj["name"] = JSONValue(name);
		obj["kind"] = JSONValue(cast(int) kind);
		if (detail.length)
			obj["detail"] = JSONValue(symbolDetail);
		obj["range"] = range.toJson();
		obj["selectionRange"] = selectionRange.toJson();
		if (children.length)
		{
			JSONValue[] childArray;
			foreach (child; children)
				childArray ~= child.toJson();
			obj["children"] = JSONValue(childArray);
		}
		return obj;
	}

	private string symbolDetail() const
	{
		return detail;
	}
}

/**
 * A markable string used for hover contents.
 */
struct MarkupContent
{
	/// "plaintext" or "markdown"
	string kind;
	string value;

	JSONValue toJson() const
	{
		JSONValue obj = parseJSON(`{}`);
		obj["kind"] = JSONValue(kind);
		obj["value"] = JSONValue(value);
		return obj;
	}
}
