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

module dcd.server.lsp.document;

import std.algorithm;
import std.array;
import std.conv;
import std.exception : enforce;
import std.string;

import dcd.server.lsp.protocol : Position;

/**
 * An open text document tracked by the server.
 */
struct TextDocument
{
	/// The document's URI.
	string uri;

	/// The current text content.
	string text;

	/// The language identifier, e.g. "d".
	string languageId;

	/// The version number of the document.
	long docVersion;

	/// Module paths ("a/b/c", DCD's internal slash-separated form) whose
	/// imports have already been warmed into the server's module cache, so
	/// that didChange only warms new ones.
	string[] warmedImports;

	/// Byte offsets of the start of each line.
	size_t[] lineStarts;

	/// Recomputes the line index from the current text.
	void reindex()
	{
		lineStarts = [0];
		foreach (i, char c; text)
		{
			if (c == '\n')
				lineStarts ~= i + 1;
		}
	}

	/// Returns the text of the given (zero-based) line, without terminator.
	string getLine(size_t line) const
	{
		enforce(line < lineStarts.length,
			"Line index out of bounds: " ~ line.to!string);
		size_t start = lineStarts[line];
		size_t end = line + 1 < lineStarts.length
			? lineStarts[line + 1]
			: text.length;
		// strip trailing \n and \r\n
		while (end > start && (text[end - 1] == '\n' || text[end - 1] == '\r'))
			end--;
		return text[start .. end];
	}

	unittest
	{
		TextDocument doc;
		doc.text = "abc\r\ndef\n\nghi";
		doc.reindex();
		assert(doc.lineStarts == [0, 5, 9, 10]);
		assert(doc.getLine(0) == "abc");
		assert(doc.getLine(1) == "def");
		assert(doc.getLine(2) == "");
		assert(doc.getLine(3) == "ghi");
	}
}

/**
 * The position encoding negotiated with the client.
 */
enum PositionEncoding
{
	/// `character` counts UTF-16 code units (LSP default).
	utf16,
	/// `character` counts UTF-8 code units (bytes).
	utf8,
}

/**
 * Converts between byte offsets and LSP positions for a document.
 */
struct PositionConverter
{
	private PositionEncoding encoding;

	this(PositionEncoding encoding)
	{
		this.encoding = encoding;
	}

	/// Converts a byte offset to an LSP position.
	Position toPosition(in TextDocument doc, size_t offset) const
	{
		enforce(offset <= doc.text.length, "Offset out of bounds");
		// binary search for the last line start <= offset
		// (lineStarts is sorted ascending and starts with 0)
		size_t lo = 0;
		size_t hi = doc.lineStarts.length - 1;
		while (lo < hi)
		{
			immutable mid = lo + (hi - lo + 1) / 2;
			if (doc.lineStarts[mid] <= offset)
				lo = mid;
			else
				hi = mid - 1;
		}
		size_t line = lo;
		size_t lineStart = doc.lineStarts[line];
		size_t byteInLine = offset - lineStart;

		size_t character;
		final switch (encoding)
		{
		case PositionEncoding.utf8:
			character = byteInLine;
			break;
		case PositionEncoding.utf16:
			character = utf16Length(doc.text[lineStart .. offset]);
			break;
		}
		return Position(line, character);
	}

	/// Converts an LSP position to a byte offset.
	size_t toOffset(in TextDocument doc, Position pos) const
	{
		enforce(pos.line < doc.lineStarts.length, "Position line out of bounds");
		size_t lineStart = doc.lineStarts[pos.line];
		size_t lineEnd = pos.line + 1 < doc.lineStarts.length
			? doc.lineStarts[pos.line + 1]
			: doc.text.length;
		size_t maxBytes = lineEnd - lineStart;

		size_t byteInLine;
		final switch (encoding)
		{
		case PositionEncoding.utf8:
			byteInLine = pos.character;
			break;
		case PositionEncoding.utf16:
			byteInLine = utf16ToByteOffset(doc.text[lineStart .. lineEnd], pos.character);
			break;
		}
		return lineStart + min(byteInLine, maxBytes);
	}

	/// Computes the length in UTF-16 code units of a UTF-8 string.
	private static size_t utf16Length(string s)
	{
		size_t units;
		foreach (dchar c; s)
			units += c >= 0x10000 ? 2 : 1;
		return units;
	}

	/// Finds the byte offset within `s` of the given UTF-16 code unit index.
	private static size_t utf16ToByteOffset(string s, size_t utf16Index)
	{
		size_t units;
		foreach (i, dchar c; s)
		{
			if (units >= utf16Index)
				return i;
			units += c >= 0x10000 ? 2 : 1;
		}
		return s.length;
	}
}

/**
 * A store of currently open documents, keyed by URI.
 */
final class DocumentStore
{
private:
	TextDocument[string] documents;
	PositionEncoding encoding = PositionEncoding.utf8;

public:
	this(PositionEncoding encoding = PositionEncoding.utf8)
	{
		this.encoding = encoding;
	}

	/// The negotiated position encoding.
	PositionEncoding positionEncoding() const @property
	{
		return encoding;
	}

	/// Registers a document as opened.
	void didOpen(string uri, string languageId, long docVersion, string text)
	{
		TextDocument doc;
		doc.uri = uri;
		doc.languageId = languageId;
		doc.docVersion = docVersion;
		doc.text = text;
		doc.reindex();
		documents[uri] = doc;
	}

	/// Replaces the content of a document (full sync).
	void didChange(string uri, long docVersion, string text)
	{
		if (auto doc = uri in documents)
		{
			doc.text = text;
			doc.docVersion = docVersion;
			doc.reindex();
		}
	}

	/// Marks a document as closed.
	void didClose(string uri)
	{
		documents.remove(uri);
	}

	/// Returns: the document for the URI, or `null` if not open.
	TextDocument* get(string uri)
	{
		return uri in documents;
	}

	unittest
	{
		auto store = new DocumentStore;
		store.didOpen("file:///a.d", "d", 1, "int x;");
		auto doc = store.get("file:///a.d");
		assert(doc !is null);
		assert(doc.text == "int x;");
		store.didChange("file:///a.d", 2, "int y;");
		assert(store.get("file:///a.d").text == "int y;");
		store.didClose("file:///a.d");
		assert(store.get("file:///a.d") is null);
	}
}

unittest
{
	// UTF-8 encoding: byte offsets pass through
	TextDocument doc;
	doc.text = "hello\nwörld";
	doc.reindex();
	auto conv = PositionConverter(PositionEncoding.utf8);
	assert(conv.toPosition(doc, 0) == Position(0, 0));
	assert(conv.toPosition(doc, 6) == Position(1, 0));
	// ö is 2 bytes in UTF-8
	assert(conv.toPosition(doc, 8) == Position(1, 2));

	// UTF-16 encoding: non-BMP aware
	TextDocument doc2;
	doc2.text = "a\U0001F600b"; // emoji is 4 bytes UTF-8, 2 units UTF-16
	doc2.reindex();
	auto conv16 = PositionConverter(PositionEncoding.utf16);
	assert(conv16.toPosition(doc2, 1) == Position(0, 1));
	assert(conv16.toPosition(doc2, 5) == Position(0, 3));
	assert(conv16.toOffset(doc2, Position(0, 3)) == 5);
}
