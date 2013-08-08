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
import modulecache;

class AutocompleteVisitor : ASTVisitor
{
	alias ASTVisitor.visit visit;

	override void visit(StructDeclaration dec)
	{
		auto symbol = new ACSymbol;
		symbol.name = dec.name.value;
		symbol.location = dec.name.startIndex;
		symbol.kind = CompletionKind.structName;
		mixin (visitAndAdd);
	}

	override void visit(ClassDeclaration dec)
	{
		auto symbol = new ACSymbol;
		symbol.name = dec.name.value;
		symbol.location = dec.name.startIndex;
		symbol.kind = CompletionKind.className;
		mixin (visitAndAdd);
	}

	override void visit(InterfaceDeclaration dec)
	{
		auto symbol = new ACSymbol;
		symbol.name = dec.name.value;
		symbol.location = dec.name.startIndex;
		symbol.kind = CompletionKind.interfaceName;
		mixin (visitAndAdd);
	}

	override void visit(StructBody structBody)
	{
		auto s = scope_;
		scope_ = new Scope(structBody.startLocation, structBody.endLocation);
		scope_.symbols ~= new ACSymbol("this", CompletionKind.variableName,
			parentSymbol);
		scope_.parent = s;
		structBody.accept(this);
		scope_ = s;
	}

	override void visit(EnumDeclaration dec)
	{
		auto symbol = new ACSymbol;
		symbol.name = dec.name.value;
		symbol.location = dec.name.startIndex;
		symbol.kind = CompletionKind.enumName;
		mixin (visitAndAdd);
	}

	override void visit(FunctionDeclaration dec)
	{
		auto symbol = new ACSymbol;
		symbol.name = dec.name.value;
		symbol.location = dec.name.startIndex;
		symbol.kind = CompletionKind.functionName;
		mixin (visitAndAdd);
	}

	override void visit(EnumMember member)
	{
		auto s = new ACSymbol;
		s.kind = CompletionKind.enumMember;
		s.name = member.name.value;
		s.location = member.name.startIndex;
		if (parentSymbol !is null)
			parentSymbol.parts ~= s;
	}

	override void visit(VariableDeclaration dec)
	{
		foreach (d; dec.declarators)
		{
			auto symbol = new ACSymbol;
			symbol.type = dec.type;
			symbol.name = d.name.value;
			symbol.location = d.name.startIndex;
			symbol.kind = CompletionKind.variableName;
			if (parentSymbol is null)
				symbols ~= symbol;
			else
				parentSymbol.parts ~= symbol;
			scope_.symbols ~= symbol;
		}
	}

	override void visit(ImportDeclaration dec)
	{
		if (!currentFile) return;
		foreach (singleImport; dec.singleImports)
		{
			scope_.symbols ~= ModuleCache.getSymbolsInModule(
				convertChainToImportPath(singleImport.identifierChain));
		}
		if (dec.importBindings !is null)
		{
			scope_.symbols ~= ModuleCache.getSymbolsInModule(
				convertChainToImportPath(
					dec.importBindings.singleImport.identifierChain));
		}
	}

	override void visit(BlockStatement blockStatement)
	{
		auto s = scope_;
		scope_ = new Scope(blockStatement.startLocation,
			blockStatement.endLocation);
		scope_.parent = s;
		blockStatement.accept(this);
		s.children ~= scope_;
		scope_ = s;
	}

	override void visit(Module mod)
	{
		scope_ = new Scope(0, size_t.max);
		mod.accept(this);
	}

	private static string convertChainToImportPath(IdentifierChain chain)
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
	string[] imports = ["object"];
	bool currentFile = false;

private:
	static enum string visitAndAdd = q{
		auto p = parentSymbol;
		parentSymbol = symbol;
		dec.accept(this);
		parentSymbol = p;
		if (parentSymbol is null)
			symbols ~= symbol;
		else
			parentSymbol.parts ~= symbol;
		scope_.symbols ~= symbol;
	};
}

void doesNothing(string, int, int, string) {}

AutocompleteVisitor processModule(const(Token)[] tokens)
{
	Module mod = parseModule(tokens, "", &doesNothing);
	auto visitor = new AutocompleteVisitor;
	visitor.currentFile = true;
	visitor.visit(mod);
	return visitor;
}
