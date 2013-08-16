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
import std.algorithm;
import std.path;
import std.range;
import std.conv;

import actypes;
import messages;
import modulecache;
import autocomplete;

class AutocompleteVisitor : ASTVisitor
{
	alias ASTVisitor.visit visit;

	override void visit(Unittest dec)
	{
//		writeln("Unitttest visit");
		auto symbol = new ACSymbol("*unittest*");
		auto p = parentSymbol;
		parentSymbol = symbol;
		dec.accept(this);
		parentSymbol = p;
	}

	override void visit(StructDeclaration dec)
	{
//		writeln("StructDeclaration visit");
		auto symbol = new ACSymbol;
		symbol.name = dec.name.value;
		symbol.location = dec.name.startIndex;
		symbol.kind = CompletionKind.structName;
		mixin (visitAndAdd);
	}

	override void visit(ClassDeclaration dec)
	{
//		writeln("ClassDeclaration visit");
		auto symbol = new ACSymbol;
		symbol.name = dec.name.value;
		symbol.location = dec.name.startIndex;
		symbol.kind = CompletionKind.className;
		mixin (visitAndAdd);
	}

	override void visit(InterfaceDeclaration dec)
	{
//		writeln("InterfaceDeclaration visit");
		auto symbol = new ACSymbol;
		symbol.name = dec.name.value;
		symbol.location = dec.name.startIndex;
		symbol.kind = CompletionKind.interfaceName;
		mixin (visitAndAdd);
	}

	override void visit(StructBody structBody)
	{
//		writeln("StructBody visit");
		auto s = scope_;
		scope_ = new Scope(structBody.startLocation, structBody.endLocation);
		scope_.symbols ~= new ACSymbol("this", CompletionKind.variableName,
			parentSymbol);
		scope_.parent = s;
		s.children ~= scope_;
		structBody.accept(this);
		scope_ = s;
	}

	override void visit(EnumDeclaration dec)
	{
		// TODO: Set enum type based on initializer of first member
//		writeln("EnumDeclaration visit");
		auto symbol = new ACSymbol;
		symbol.name = dec.name.value;
		symbol.location = dec.name.startIndex;
		symbol.kind = CompletionKind.enumName;
		auto type = dec.type;
		auto p = parentSymbol;
		parentSymbol = symbol;

		if (dec.enumBody !is null)
		{
			Scope enumBodyScope = new Scope(dec.enumBody.startLocation,
				dec.enumBody.endLocation);
			foreach (member; dec.enumBody.enumMembers)
			{
				auto s = new ACSymbol;
				s.kind = CompletionKind.enumMember;
				s.name = member.name.value;
				s.location = member.name.startIndex;
				if (type is null)
					s.resolvedType = scope_.findSymbolsInScope("int")[0];
				else
					s.type = type;
				if (parentSymbol !is null)
					parentSymbol.parts ~= s;
				enumBodyScope.symbols ~= s;
			}
			enumBodyScope.parent = scope_;
			scope_.children ~= enumBodyScope;
		}

		parentSymbol = p;
		if (parentSymbol is null)
			symbols ~= symbol;
		else
			parentSymbol.parts ~= symbol;
		scope_.symbols ~= symbol;
	}

	override void visit(Constructor dec)
	{
		ACSymbol symbol = new ACSymbol("*constructor*");
		symbol.location = dec.location;
		symbol.kind = CompletionKind.functionName;
		//symbol.type = dec.returnType;

		ACSymbol[] parameterSymbols;
		if (dec.parameters !is null)
		{
			foreach (parameter; dec.parameters.parameters)
			{
//				writeln("Adding parameter ", parameter.name.value);
				ACSymbol paramSymbol = new ACSymbol;
				paramSymbol.name = parameter.name.value;
				paramSymbol.type = parameter.type;
				paramSymbol.kind = CompletionKind.variableName;
				paramSymbol.location = parameter.name.startIndex;
				parameterSymbols ~= paramSymbol;
			}
		}

		if (dec.parameters !is null && parentSymbol !is null)
		{           
			symbol.calltip = format("%s this%s", parentSymbol.name,
				dec.parameters.toString());
		}
		auto p = parentSymbol;
		parentSymbol = symbol;

		BlockStatement functionBody = dec.functionBody is null ? null
			: (dec.functionBody.bodyStatement !is null
			? dec.functionBody.bodyStatement.blockStatement : dec.functionBody.blockStatement);

		if (functionBody !is null)
		{
			auto s = scope_;
			scope_ = new Scope(functionBody.startLocation,
				functionBody.endLocation);
			scope_.parent = s;
			foreach (parameterSymbol; parameterSymbols)
			{
				parameterSymbol.location = functionBody.startLocation;
				scope_.symbols ~= parameterSymbol;
			}
			if (functionBody.declarationsAndStatements !is null)
				functionBody.declarationsAndStatements.accept(this);
			s.children ~= scope_;
			scope_ = s;
		}

		parentSymbol = p;
		if (parentSymbol is null)
			symbols ~= symbol;
		else
			parentSymbol.parts ~= symbol;
		scope_.symbols ~= symbol;
	}

	override void visit(FunctionDeclaration dec)
	{
		ACSymbol symbol = new ACSymbol;
		symbol.name = dec.name.value;
		symbol.location = dec.name.startIndex;
		symbol.kind = CompletionKind.functionName;
		symbol.type = dec.returnType;

		ACSymbol[] parameterSymbols;
		if (dec.parameters !is null)
		{
			foreach (parameter; dec.parameters.parameters)
			{
//				writeln("Adding parameter ", parameter.name.value);
				ACSymbol paramSymbol = new ACSymbol;
				paramSymbol.name = parameter.name.value;
				paramSymbol.type = parameter.type;
				paramSymbol.kind = CompletionKind.variableName;
				paramSymbol.location = parameter.name.startIndex;
				parameterSymbols ~= paramSymbol;
			}
		}

		if (dec.returnType !is null && dec.parameters !is null)
		{
			symbol.calltip = format("%s %s%s", dec.returnType.toString(),
				dec.name.value, dec.parameters.toString());
		}
		auto p = parentSymbol;
		parentSymbol = symbol;

		BlockStatement functionBody = dec.functionBody is null ? null
			: (dec.functionBody.bodyStatement !is null
			? dec.functionBody.bodyStatement.blockStatement : dec.functionBody.blockStatement);

		if (functionBody !is null)
		{
			auto s = scope_;
			scope_ = new Scope(functionBody.startLocation,
				functionBody.endLocation);
			scope_.parent = s;
			foreach (parameterSymbol; parameterSymbols)
			{
				parameterSymbol.location = functionBody.startLocation;
				scope_.symbols ~= parameterSymbol;
			}
			if (functionBody.declarationsAndStatements !is null)
				functionBody.declarationsAndStatements.accept(this);
			s.children ~= scope_;
			scope_ = s;
		}

		parentSymbol = p;
		if (parentSymbol is null)
			symbols ~= symbol;
		else
			parentSymbol.parts ~= symbol;
		scope_.symbols ~= symbol;
	}

	override void visit(VariableDeclaration dec)
	{
//		writeln("VariableDeclaration visit");
		foreach (d; dec.declarators)
		{
			ACSymbol symbol = new ACSymbol;
			if (dec.type.typeSuffixes.length > 0
				&& dec.type.typeSuffixes[$-1].delegateOrFunction != TokenType.invalid)
			{
				TypeSuffix suffix = dec.type.typeSuffixes[$ - 1];
				dec.type.typeSuffixes = dec.type.typeSuffixes[0 .. $ - 1];
				symbol.calltip = "%s %s%s".format(dec.type,
					suffix.delegateOrFunction.value,
					suffix.parameters.toString());
			}
			symbol.kind = CompletionKind.variableName;

			symbol.type = dec.type;
			symbol.name = d.name.value;
			symbol.location = d.name.startIndex;

			if (parentSymbol is null)
				symbols ~= symbol;
			else
				parentSymbol.parts ~= symbol;
			scope_.symbols ~= symbol;
		}
	}

	override void visit(AliasDeclaration dec)
	{
		if (dec.type is null) foreach (aliasPart; dec.initializers)
		{
			ACSymbol aliasSymbol = new ACSymbol;
			aliasSymbol.kind = CompletionKind.aliasName;
			aliasSymbol.location = aliasPart.name.startIndex;
			aliasSymbol.type = aliasPart.type;
			if (aliasPart.type.typeSuffixes.length > 0
				&& aliasPart.type.typeSuffixes[$-1].delegateOrFunction != TokenType.invalid)
			{
				TypeSuffix suffix = aliasPart.type.typeSuffixes[$ - 1];
				aliasPart.type.typeSuffixes = aliasPart.type.typeSuffixes[0 .. $ - 1];
				aliasSymbol.calltip = "%s %s%s".format(dec.type,
					suffix.delegateOrFunction.value,
					suffix.parameters.toString());
			}
			if (parentSymbol is null)
				symbols ~= aliasSymbol;
			else
				parentSymbol.parts ~= aliasSymbol;
			scope_.symbols ~= aliasSymbol;
		}
		else
		{
//			writeln("Visiting alias declaration ", dec.name.value);
			ACSymbol aliasSymbol = new ACSymbol;
			aliasSymbol.kind = CompletionKind.aliasName;
			aliasSymbol.name = dec.name.value;
			aliasSymbol.type = dec.type;
			if (dec.type.typeSuffixes.length > 0
				&& dec.type.typeSuffixes[$-1].delegateOrFunction != TokenType.invalid)
			{
				TypeSuffix suffix = dec.type.typeSuffixes[$ - 1];
				dec.type.typeSuffixes = dec.type.typeSuffixes[0 .. $ - 1];
				aliasSymbol.calltip = "%s %s%s".format(dec.type,
					suffix.delegateOrFunction.value,
					suffix.parameters.toString());
			}
			aliasSymbol.location = dec.name.startIndex;
			if (parentSymbol is null)
				symbols ~= aliasSymbol;
			else
				parentSymbol.parts ~= aliasSymbol;
			scope_.symbols ~= aliasSymbol;
		}

	}

	override void visit(ImportDeclaration dec)
	{
		// TODO: handle public imports
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
		scope_.symbols ~= builtinSymbols;
		mod.accept(this);
	}

	private static string convertChainToImportPath(IdentifierChain chain)
	{
		return to!string(chain.identifiers.map!"a.value"().join(dirSeparator).array) ~ ".d";
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
