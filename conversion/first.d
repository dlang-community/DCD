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

module conversion.first;

import stdx.d.ast;
import stdx.d.lexer;
import actypes;
import semantic;
import messages;
import stupidlog;

/**
 * First Pass handles the following:
 * $(UL
 *     $(LI symbol name)
 *     $(LI symbol location)
 *     $(LI alias this locations)
 *     $(LI base class names)
 *     $(LI protection level)
 *     $(LI symbol kind)
 *     $(LI function call tip)
 *     $(LI symbol file path)
 * )
 */
final class FirstPass : ASTVisitor
{
	this(Module mod, string symbolFile, shared(StringCache)* stringCache)
	{
		this.symbolFile = symbolFile;
		this.mod = mod;
		this.stringCache = stringCache;
	}

	void run()
	{
		visit(mod);
		mod = null;
	}

	override void visit(const Unittest u)
	{
		// Create a dummy symbol because we don't want unit test symbols leaking
		// into the symbol they're declared in.
		SemanticSymbol* s = new SemanticSymbol("*unittest*",
			CompletionKind.dummy, null, 0);
		s.parent = currentSymbol;
		currentSymbol = s;
		u.accept(this);
		currentSymbol = s.parent;
	}

	override void visit(const Constructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, con.parameters, con.functionBody, con.comment);
	}

	override void visit(const SharedStaticConstructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, null, con.functionBody, con.comment);
	}

	override void visit(const StaticConstructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, null, con.functionBody, con.comment);
	}

	override void visit(const Destructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.location, des.functionBody, des.comment);
	}

	override void visit(const SharedStaticDestructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.location, des.functionBody, des.comment);
	}

	override void visit(const StaticDestructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.location, des.functionBody, des.comment);
	}

	override void visit(const FunctionDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		SemanticSymbol* symbol = new SemanticSymbol(stringCache.intern(dec.name.text),
			CompletionKind.functionName, symbolFile, dec.name.index, dec.returnType);
		processParameters(symbol, dec.returnType, symbol.acSymbol.name,
			dec.parameters, dec.comment);
		symbol.protection = protection;
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = dec.comment;
		currentSymbol.addChild(symbol);
		if (dec.functionBody !is null)
		{
			currentSymbol = symbol;
			dec.functionBody.accept(this);
			currentSymbol = symbol.parent;
		}
	}

	override void visit(const ClassDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.className);
	}

	override void visit(const TemplateDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.templateName);
	}

	override void visit(const InterfaceDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.interfaceName);
	}

	override void visit(const UnionDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.unionName);
	}

	override void visit(const StructDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.structName);
	}

	override void visit(const BaseClass bc)
	{
//		Log.trace(__FUNCTION__, " ", typeof(bc).stringof);
		currentSymbol.baseClasses ~= iotcToStringArray(
			bc.identifierOrTemplateChain, stringCache);
	}

	override void visit(const VariableDeclaration dec)
	{
		assert (currentSymbol);
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		const Type t = dec.type;
		foreach (declarator; dec.declarators)
		{
			SemanticSymbol* symbol = new SemanticSymbol(
				stringCache.intern(declarator.name.text),
				CompletionKind.variableName,
				symbolFile,
				declarator.name.index,
				t);
			symbol.protection = protection;
			symbol.parent = currentSymbol;
			symbol.acSymbol.doc = dec.comment;
			currentSymbol.addChild(symbol);
		}
		if (dec.autoDeclaration !is null)
		{
			foreach (identifier; dec.autoDeclaration.identifiers)
			{
				SemanticSymbol* symbol = new SemanticSymbol(
					stringCache.intern(identifier.text),
					CompletionKind.variableName, symbolFile, identifier.index,
					null);
				symbol.protection = protection;
				symbol.parent = currentSymbol;
				symbol.acSymbol.doc = dec.comment;
				currentSymbol.addChild(symbol);
			}
		}
	}

	override void visit(const AliasDeclaration aliasDeclaration)
	{
		if (aliasDeclaration.initializers.length == 0)
		{
			SemanticSymbol* symbol = new SemanticSymbol(
				stringCache.intern(aliasDeclaration.name.text),
				CompletionKind.aliasName,
				symbolFile,
				aliasDeclaration.name.index,
				aliasDeclaration.type);
			symbol.protection = protection;
			symbol.parent = currentSymbol;
			symbol.acSymbol.doc = aliasDeclaration.comment;
			currentSymbol.addChild(symbol);
		}
		else
		{
			foreach (initializer; aliasDeclaration.initializers)
			{
				SemanticSymbol* symbol = new SemanticSymbol(
					stringCache.intern(initializer.name.text),
					CompletionKind.aliasName,
					symbolFile,
					initializer.name.index,
					initializer.type);
				symbol.protection = protection;
				symbol.parent = currentSymbol;
				symbol.acSymbol.doc = aliasDeclaration.comment;
				currentSymbol.addChild(symbol);
			}
		}
	}

	override void visit(const AliasThisDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		currentSymbol.aliasThis ~= stringCache.intern(dec.identifier.text);
	}

	override void visit(const Declaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		if (dec.attributeDeclaration !is null
			&& isProtection(dec.attributeDeclaration.attribute.attribute))
		{
			protection = dec.attributeDeclaration.attribute.attribute;
			return;
		}
		IdType p = protection;
		foreach (const Attribute attr; dec.attributes)
		{
			if (isProtection(attr.attribute))
				protection = attr.attribute;
		}
		dec.accept(this);
		protection = p;
	}

	override void visit(const Module mod)
	{
//		Log.trace(__FUNCTION__, " ", typeof(mod).stringof);
//
		currentSymbol = new SemanticSymbol(null, CompletionKind.moduleName,
			symbolFile);
		rootSymbol = currentSymbol;
		currentScope = new Scope(0, size_t.max);
		ImportInformation i;
		i.modulePath = "object";
		i.importParts ~= "object";
		currentScope.importInformation ~= i;
		moduleScope = currentScope;
		mod.accept(this);
	}

	override void visit(const EnumDeclaration dec)
	{
		assert (currentSymbol);
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		SemanticSymbol* symbol = new SemanticSymbol(stringCache.intern(dec.name.text),
			CompletionKind.enumName, symbolFile, dec.name.index, dec.type);
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = dec.comment;
		currentSymbol = symbol;
		if (dec.enumBody !is null)
			dec.enumBody.accept(this);
		currentSymbol = symbol.parent;
		currentSymbol.addChild(symbol);
	}

	override void visit(const EnumMember member)
	{
//		Log.trace(__FUNCTION__, " ", typeof(member).stringof);
		SemanticSymbol* symbol = new SemanticSymbol(stringCache.intern(member.name.text),
			CompletionKind.enumMember, symbolFile, member.name.index, member.type);
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = member.comment;
		currentSymbol.addChild(symbol);
	}

	override void visit(const ModuleDeclaration moduleDeclaration)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		foreach (identifier; moduleDeclaration.moduleName.identifiers)
		{
			moduleName ~= stringCache.intern(identifier.text);
		}
	}

	// creates scopes for
	override void visit(const StructBody structBody)
	{
//		Log.trace(__FUNCTION__, " ", typeof(structBody).stringof);
		Scope* s = new Scope(structBody.startLocation, structBody.endLocation);
//		Log.trace("Added scope ", s.startLocation, " ", s.endLocation);

		ACSymbol* thisSymbol = new ACSymbol("this", CompletionKind.variableName,
			currentSymbol.acSymbol);
		thisSymbol.location = s.startLocation;
		thisSymbol.symbolFile = symbolFile;
		currentSymbol.acSymbol.parts.insert(thisSymbol);

		s.parent = currentScope;
		currentScope = s;
		foreach (dec; structBody.declarations)
			visit(dec);
		currentScope = s.parent;
		currentScope.children ~= s;
	}

	override void visit(const ImportDeclaration importDeclaration)
	{
		import std.typecons;
		import std.algorithm;
		import std.array;
//		Log.trace(__FUNCTION__, " ImportDeclaration");
		foreach (single; importDeclaration.singleImports.filter!(
			a => a !is null && a.identifierChain !is null))
		{
			ImportInformation info;
			info.importParts = single.identifierChain.identifiers.map!(a => stringCache.intern(a.text)).array;
			info.modulePath = convertChainToImportPath(single.identifierChain);
			info.isPublic = protection == tok!"public";
			currentScope.importInformation ~= info;
		}
		if (importDeclaration.importBindings is null) return;
		if (importDeclaration.importBindings.singleImport.identifierChain is null) return;
		ImportInformation info;
		info.modulePath = convertChainToImportPath(
			importDeclaration.importBindings.singleImport.identifierChain);
		info.importParts = importDeclaration.importBindings.singleImport
			.identifierChain.identifiers.map!(a => stringCache.intern(a.text)).array;
		foreach (bind; importDeclaration.importBindings.importBinds)
		{
			Tuple!(string, string) bindTuple;
			bindTuple[0] = stringCache.intern(bind.left.text);
			bindTuple[1] = bind.right == tok!"" ? null : stringCache.intern(bind.right.text);
			info.importedSymbols ~= bindTuple;
		}
		info.isPublic = protection == tok!"public";
		currentScope.importInformation ~= info;
	}

	// Create scope for block statements
	override void visit(const BlockStatement blockStatement)
	{
//		Log.trace(__FUNCTION__, " ", typeof(blockStatement).stringof);
		Scope* s = new Scope(blockStatement.startLocation,
			blockStatement.endLocation);
		s.parent = currentScope;
		currentScope.children ~= s;

		if (currentSymbol.acSymbol.kind == CompletionKind.functionName)
		{
			foreach (child; currentSymbol.children)
			{
				if (child.acSymbol.location == size_t.max)
				{
//					Log.trace("Reassigning location of ", child.acSymbol.name);
					child.acSymbol.location = s.startLocation + 1;
				}
			}
		}
		if (blockStatement.declarationsAndStatements !is null)
		{
			currentScope = s;
			visit (blockStatement.declarationsAndStatements);
			currentScope = s.parent;
		}
	}

	override void visit(const VersionCondition versionCondition)
	{
		import std.algorithm;
		import constants;
		// TODO: This is a bit of a hack
		if (predefinedVersions.canFind(versionCondition.token.text))
			versionCondition.accept(this);
	}

	alias visit = ASTVisitor.visit;

	/// Module scope
	Scope* moduleScope;

	/// The module
	SemanticSymbol* rootSymbol;

	shared(StringCache)* stringCache;

private:

	void visitAggregateDeclaration(AggType)(AggType dec, CompletionKind kind)
	{
//		Log.trace("visiting aggregate declaration ", dec.name.text);
		SemanticSymbol* symbol = new SemanticSymbol(stringCache.intern(dec.name.text),
			kind, symbolFile, dec.name.index);
		if (kind == CompletionKind.className)
			symbol.acSymbol.parts.insert(classSymbols[]);
		else
			symbol.acSymbol.parts.insert(aggregateSymbols[]);
		symbol.parent = currentSymbol;
		symbol.protection = protection;
		symbol.acSymbol.doc = dec.comment;
		currentSymbol = symbol;
		dec.accept(this);
		currentSymbol = symbol.parent;
		currentSymbol.addChild(symbol);
	}

	void visitConstructor(size_t location, const Parameters parameters,
		const FunctionBody functionBody, string doc)
	{
		SemanticSymbol* symbol = new SemanticSymbol("*constructor*",
			CompletionKind.functionName, symbolFile, location);
		processParameters(symbol, null, "this", parameters, doc);
		symbol.protection = protection;
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = doc;
		currentSymbol.addChild(symbol);
		if (functionBody !is null)
		{
			currentSymbol = symbol;
			functionBody.accept(this);
			currentSymbol = symbol.parent;
		}
	}

	void visitDestructor(size_t location, const FunctionBody functionBody, string doc)
	{
		SemanticSymbol* symbol = new SemanticSymbol("~this",
			CompletionKind.functionName, symbolFile, location);
		symbol.acSymbol.callTip = "~this()";
		symbol.protection = protection;
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = doc;
		currentSymbol.addChild(symbol);
		if (functionBody !is null)
		{
			currentSymbol = symbol;
			functionBody.accept(this);
			currentSymbol = symbol.parent;
		}
	}

	void processParameters(SemanticSymbol* symbol, const Type returnType,
		string functionName, const Parameters parameters, string doc)
	{
		if (parameters !is null)
		{
			foreach (const Parameter p; parameters.parameters)
			{
				SemanticSymbol* parameter = new SemanticSymbol(
					stringCache.intern(p.name.text),
					CompletionKind.variableName, symbolFile, size_t.max,
					p.type);
				symbol.addChild(parameter);
				parameter.parent = symbol;
			}
			if (parameters.hasVarargs)
			{
				SemanticSymbol* argptr = new SemanticSymbol("_argptr",
					CompletionKind.variableName, null, size_t.max, argptrType);
				argptr.parent = symbol;
				symbol.addChild(argptr);

				SemanticSymbol* arguments = new SemanticSymbol("_arguments",
					CompletionKind.variableName, null, size_t.max, argumentsType);
				arguments.parent = symbol;
				symbol.addChild(arguments);
			}
		}
		symbol.acSymbol.callTip = formatCallTip(returnType, functionName,
			parameters, doc);
	}

	static string formatCallTip(const Type returnType, string name,
		const Parameters parameters, string doc = null)
	{
		import std.string;
		string parameterString = parameters is null ? "()"
			: formatNode(parameters);
		if (returnType is null)
			return "%s%s".format(name, parameterString);
		return "%s %s%s".format(formatNode(returnType), name, parameterString);
	}

	/// Current protection type
	IdType protection;

	/// Package and module name
	string[] moduleName;

	/// Current scope
	Scope* currentScope;

	/// Current symbol
	SemanticSymbol* currentSymbol;

	/// Path to the file being converted
	string symbolFile;

	Module mod;
}

string formatNode(T)(const T node)
{
	import formatter;
	import std.array;
	import std.conv;
	if (node is null) return "";
	auto app = appender!(char[])();
	auto f = new Formatter!(typeof(app))(app);
	f.format(node);
	return to!string(app.data);
}

private:

string[] iotcToStringArray(const IdentifierOrTemplateChain iotc,
	shared(StringCache)* stringCache)
{
	string[] parts;
	foreach (ioti; iotc.identifiersOrTemplateInstances)
	{
		if (ioti.identifier != tok!"")
			parts ~= stringCache.intern(ioti.identifier.text);
		else
			parts ~= stringCache.intern(ioti.templateInstance.identifier.text);
	}
	return parts;
}

private static string convertChainToImportPath(const IdentifierChain ic)
{
	import std.conv;
	import std.algorithm;
	import std.range;
	import std.path;
	return to!string(ic.identifiers.map!(a => cast() a.text).join(dirSeparator).array);
}
