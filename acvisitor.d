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

module acvisitor;

import std.file;
import stdx.d.parser;
import stdx.d.ast;
import stdx.d.lexer;
import std.stdio;

import actypes;
import messages;

class AutoCompleteVisitor : ASTVisitor
{
	alias ASTVisitor.visit visit;

	override void visit(EnumDeclaration enumDec)
	{
		auto symbol = new ACSymbol;
		symbol.name = enumDec.name.value;
		symbol.kind = CompletionKind.enumName;
		auto p = parentSymbol;
		parentSymbol = symbol;
		enumDec.accept(this);
		parentSymbol = p;
		writeln("Added ", symbol.name);
		if (parentSymbol is null)
			symbols ~= symbol;
		else
			parentSymbol.parts ~= symbol;
		scope_.symbols ~= symbol;
	}

	override void visit(EnumMember member)
	{
		auto s = new ACSymbol;
		s.kind = CompletionKind.enumMember;
		s.name = member.name.value;
		writeln("Added enum member ", s.name);
		if (parentSymbol !is null)
			parentSymbol.parts ~= s;
	}

	override void visit(ImportDeclaration dec)
	{
		foreach (singleImport; dec.singleImports)
		{
			imports ~= flattenIdentifierChain(singleImport.identifierChain);
		}
		if (dec.importBindings !is null)
		{
			imports ~= flattenIdentifierChain(dec.importBindings.singleImport.identifierChain);
		}
	}

	override void visit(BlockStatement blockStatement)
	{
		auto s = scope_;
		scope_ = new Scope(blockStatement.startLocation,
			blockStatement.endLocation);
		blockStatement.accept(this);
		s.children ~= scope_;
		scope_ = s;
	}

	override void visit(Module mod)
	{
		scope_ = new Scope(0, size_t.max);
		mod.accept(this);
	}

	private static string flattenIdentifierChain(IdentifierChain chain)
	{
		string rVal;
		bool first = true;
		foreach (identifier; chain.identifiers)
		{
			if (!first)
				rVal ~= "/";
			rVal ~= identifier.value;
			first = false;
		}
		rVal ~= ".d";
		return rVal;
	}

	ACSymbol[] symbols;
	ACSymbol parentSymbol;
	Scope scope_;
	string[] imports;
}

void doesNothing(string, int, int, string) {}

AutoCompleteVisitor processModule(const(Token)[] tokens)
{
	Module mod = parseModule(tokens, "", &doesNothing);
	auto visitor = new AutoCompleteVisitor;
	visitor.visit(mod);
	return visitor;
}

string[] getImportedFiles(string[] imports, string[] importPaths)
{
	string[] importedFiles;
	foreach (imp; imports)
	{
		bool found = false;
		foreach (path; importPaths)
		{
			string filePath = path ~ "/" ~ imp;
			if (filePath.exists())
			{
				importedFiles ~= filePath;
				found = true;
				break;
			}
			filePath ~= "i"; // check for x.di if x.d isn't found
			if (filePath.exists())
			{
				importedFiles ~= filePath;
				found = true;
				break;
			}
		}
		if (!found)
			writeln("Could not locate ", imp);
	}
	return importedFiles;
}
