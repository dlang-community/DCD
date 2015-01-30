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

import actypes;
import std.d.formatter;
import std.allocator;
import memory.allocators;
import memory.appender;
import messages;
import semantic;
import std.d.ast;
import std.d.lexer;
import std.typecons;
import stupidlog;
import containers.unrolledlist;
import string_interning;

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
	/**
	 * Params:
	 *     mod = the module to visit
	 *     symbolFile = path to the file being converted
	 *     symbolAllocator = allocator used for the auto-complete symbols
	 *     semanticAllocator = allocator used for semantic symbols
	 */
	this(Module mod, string symbolFile, CAllocator symbolAllocator,
		CAllocator semanticAllocator)
	in
	{
		assert (mod);
		assert (symbolAllocator);
		assert (semanticAllocator);
	}
	body
	{
		this.mod = mod;
		this.symbolFile = symbolFile;
		this.symbolAllocator = symbolAllocator;
		this.semanticAllocator = semanticAllocator;
	}

	/**
	 * Runs the against the AST and produces symbols.
	 */
	void run()
	{
		visit(mod);
	}

	override void visit(const Unittest u)
	{
		// Create a dummy symbol because we don't want unit test symbols leaking
		// into the symbol they're declared in.
		SemanticSymbol* s = allocateSemanticSymbol(internString("*unittest*"),
			CompletionKind.dummy, null, 0);
		s.parent = currentSymbol;
		currentSymbol.addChild(s);
		currentSymbol = s;
		u.accept(this);
		currentSymbol = s.parent;
	}

	override void visit(const Constructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, con.parameters, con.templateParameters, con.functionBody, con.comment);
	}

	override void visit(const SharedStaticConstructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, null, null, con.functionBody, con.comment);
	}

	override void visit(const StaticConstructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, null, null, con.functionBody, con.comment);
	}

	override void visit(const Destructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.index, des.functionBody, des.comment);
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
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof, " ", dec.name.text);
		SemanticSymbol* symbol = allocateSemanticSymbol(dec.name.text,
			CompletionKind.functionName, symbolFile, dec.name.index,
			dec.returnType);
		processParameters(symbol, dec.returnType, symbol.acSymbol.name,
			dec.parameters, dec.templateParameters);
		symbol.protection = protection;
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = internString(dec.comment);
		currentSymbol.addChild(symbol);
		if (dec.functionBody !is null)
		{
			Scope* s = createFunctionScope(dec.functionBody, semanticAllocator,
				dec.name.index + dec.name.text.length);
			currentScope.children.insert(s);
			s.parent = currentScope;
			currentScope = s;
			currentSymbol = symbol;
			dec.functionBody.accept(this);
			currentSymbol = symbol.parent;
			currentScope = s.parent;
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
		if (bc.type2.symbol !is null && bc.type2.symbol.identifierOrTemplateChain !is null)
		{
			currentSymbol.baseClasses.insert(iotcToStringArray(symbolAllocator,
				bc.type2.symbol.identifierOrTemplateChain));
		}
	}

	override void visit(const VariableDeclaration dec)
	{
		assert (currentSymbol);
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		const Type t = dec.type;
		foreach (declarator; dec.declarators)
		{
			SemanticSymbol* symbol = allocateSemanticSymbol(
				declarator.name.text, CompletionKind.variableName,
				symbolFile, declarator.name.index, t);
			symbol.protection = protection;
			symbol.parent = currentSymbol;
			symbol.acSymbol.doc = internString(dec.comment);
			currentSymbol.addChild(symbol);
		}
		if (dec.autoDeclaration !is null)
		{
			foreach (i, identifier; dec.autoDeclaration.identifiers)
			{
				SemanticSymbol* symbol = allocateSemanticSymbol(
					identifier.text, CompletionKind.variableName, symbolFile,
					identifier.index, null);
				populateInitializer(symbol, dec.autoDeclaration.initializers[i]);
				symbol.protection = protection;
				symbol.parent = currentSymbol;
				symbol.acSymbol.doc = internString(dec.comment);
				currentSymbol.addChild(symbol);
			}
		}
	}

	override void visit(const AliasDeclaration aliasDeclaration)
	{
		if (aliasDeclaration.initializers.length == 0)
		{
			foreach (name; aliasDeclaration.identifierList.identifiers)
			{
				SemanticSymbol* symbol = allocateSemanticSymbol(
					name.text,
					CompletionKind.aliasName,
					symbolFile,
					name.index,
					aliasDeclaration.type);
				symbol.protection = protection;
				symbol.parent = currentSymbol;
				symbol.acSymbol.doc = internString(aliasDeclaration.comment);
				currentSymbol.addChild(symbol);
			}
		}
		else
		{
			foreach (initializer; aliasDeclaration.initializers)
			{
				SemanticSymbol* symbol = allocateSemanticSymbol(
					initializer.name.text,
					CompletionKind.aliasName,
					symbolFile,
					initializer.name.index,
					initializer.type);
				symbol.protection = protection;
				symbol.parent = currentSymbol;
				symbol.acSymbol.doc = internString(aliasDeclaration.comment);
				currentSymbol.addChild(symbol);
			}
		}
	}

	override void visit(const AliasThisDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		currentSymbol.aliasThis.insert(internString(dec.identifier.text));
	}

	override void visit(const Declaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		if (dec.attributeDeclaration !is null
			&& isProtection(dec.attributeDeclaration.attribute.attribute.type))
		{
			protection = dec.attributeDeclaration.attribute.attribute.type;
			return;
		}
		immutable IdType p = protection;
		foreach (const Attribute attr; dec.attributes)
		{
			if (isProtection(attr.attribute.type))
				protection = attr.attribute.type;
		}
		dec.accept(this);
		protection = p;
	}

	override void visit(const Module mod)
	{
//		Log.trace(__FUNCTION__, " ", typeof(mod).stringof);
//
		currentSymbol = allocateSemanticSymbol(null, CompletionKind.moduleName,
			symbolFile);
		rootSymbol = currentSymbol;
		currentScope = allocate!Scope(semanticAllocator, 0, size_t.max);
		auto i = allocate!ImportInformation(semanticAllocator);
		i.modulePath = internString("object");
		i.importParts.insert(i.modulePath);
		currentScope.importInformation.insert(i);
		moduleScope = currentScope;
		mod.accept(this);
	}

	override void visit(const EnumDeclaration dec)
	{
		assert (currentSymbol);
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		SemanticSymbol* symbol = allocateSemanticSymbol(dec.name.text,
			CompletionKind.enumName, symbolFile, dec.name.index, dec.type);
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = internString(dec.comment);
		currentSymbol = symbol;
		if (dec.enumBody !is null)
			dec.enumBody.accept(this);
		currentSymbol = symbol.parent;
		currentSymbol.addChild(symbol);
	}

	mixin visitEnumMember!EnumMember;
	mixin visitEnumMember!AnonymousEnumMember;

	override void visit(const ModuleDeclaration moduleDeclaration)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		rootSymbol.acSymbol.name = internString(moduleDeclaration.moduleName.identifiers[$ - 1].text);
	}

	override void visit(const StructBody structBody)
	{
//		Log.trace(__FUNCTION__, " ", typeof(structBody).stringof);
		Scope* s = allocate!Scope(semanticAllocator, structBody.startLocation, structBody.endLocation);
//		Log.trace("Added scope ", s.startLocation, " ", s.endLocation);

		ACSymbol* thisSymbol = allocate!ACSymbol(symbolAllocator, "this",
			CompletionKind.variableName, currentSymbol.acSymbol);
		thisSymbol.location = s.startLocation;
		thisSymbol.symbolFile = symbolFile;
		s.symbols.insert(thisSymbol);

		s.parent = currentScope;
		currentScope = s;
		foreach (dec; structBody.declarations)
			visit(dec);
		currentScope = s.parent;
		currentScope.children.insert(s);
	}

	override void visit(const ImportDeclaration importDeclaration)
	{
		import std.typecons : Tuple;
		import std.algorithm : filter;
//		Log.trace(__FUNCTION__, " ImportDeclaration");
		foreach (single; importDeclaration.singleImports.filter!(
			a => a !is null && a.identifierChain !is null))
		{
			auto info = allocate!ImportInformation(semanticAllocator);
			foreach (identifier; single.identifierChain.identifiers)
				info.importParts.insert(internString(identifier.text));
			info.modulePath = convertChainToImportPath(single.identifierChain);
			info.isPublic = protection == tok!"public";
			currentScope.importInformation.insert(info);
		}
		if (importDeclaration.importBindings is null) return;
		if (importDeclaration.importBindings.singleImport.identifierChain is null) return;
		auto info = allocate!ImportInformation(semanticAllocator);

		info.modulePath = convertChainToImportPath(
			importDeclaration.importBindings.singleImport.identifierChain);
		foreach (identifier; importDeclaration.importBindings.singleImport
			.identifierChain.identifiers)
		{
			info.importParts.insert(internString(identifier.text));
		}
		foreach (bind; importDeclaration.importBindings.importBinds)
		{
			Tuple!(string, string) bindTuple;
			if (bind.right == tok!"")
			{
				bindTuple[1] = internString(bind.left.text);
			}
			else
			{
				bindTuple[0] = internString(bind.left.text);
				bindTuple[1] = internString(bind.right.text);
			}
			info.importedSymbols.insert(bindTuple);
		}
		info.isPublic = protection == tok!"public";
		currentScope.importInformation.insert(info);
	}

	// Create scope for block statements
	override void visit(const BlockStatement blockStatement)
	{
//		Log.trace(__FUNCTION__, " ", typeof(blockStatement).stringof);
		Scope* s = allocate!Scope(semanticAllocator, blockStatement.startLocation,
			blockStatement.endLocation);
		s.parent = currentScope;
		currentScope.children.insert(s);

		if (blockStatement.declarationsAndStatements !is null)
		{
			currentScope = s;
			visit (blockStatement.declarationsAndStatements);
			currentScope = s.parent;
		}
	}

	override void visit(const VersionCondition versionCondition)
	{
		import std.algorithm : canFind;
		import constants : predefinedVersions;
		// TODO: This is a bit of a hack
		if (predefinedVersions.canFind(versionCondition.token.text))
			versionCondition.accept(this);
	}

	override void visit(const TemplateMixinExpression tme)
	{
		// TODO: support typeof here
		if (tme.mixinTemplateName.symbol is null)
			return;
		currentSymbol.mixinTemplates.insert(iotcToStringArray(symbolAllocator,
			tme.mixinTemplateName.symbol.identifierOrTemplateChain));
	}

	override void visit(const ForeachStatement feStatement)
	{
		if (feStatement.declarationOrStatement !is null
			&& feStatement.declarationOrStatement.statement !is null
			&& feStatement.declarationOrStatement.statement.statementNoCaseNoDefault !is null
			&& feStatement.declarationOrStatement.statement.statementNoCaseNoDefault.blockStatement !is null)
		{
			const BlockStatement bs =
				feStatement.declarationOrStatement.statement.statementNoCaseNoDefault.blockStatement;
			Scope* s = allocate!Scope(semanticAllocator, feStatement.startIndex, bs.endLocation);
			s.parent = currentScope;
			currentScope.children.insert(s);
			currentScope = s;
			feExpression = feStatement.low.items[$ - 1];
			feStatement.accept(this);
			feExpression = null;
			currentScope = currentScope.parent;
		}
		else
			feStatement.accept(this);
	}

	override void visit(const ForeachTypeList feTypeList)
	{
		if (feTypeList.items.length == 1)
			feTypeList.accept(this);
	}

	override void visit(const ForeachType feType)
	{
//		Log.trace("Handling foreachtype ", feType.identifier.text);
		SemanticSymbol* symbol = allocateSemanticSymbol(
				feType.identifier.text, CompletionKind.variableName,
				symbolFile, feType.identifier.index, feType.type);
		if (symbol.type is null && feExpression !is null)
		{
//			Log.trace("Populating initializer");
			populateInitializer(symbol, feExpression, true);
//			Log.trace(symbol.initializer[]);
		}
		symbol.parent = currentSymbol;
		currentSymbol.addChild(symbol);
	}

	override void visit(const WithStatement withStatement)
	{
		if (withStatement.expression !is null
			&& withStatement.statementNoCaseNoDefault !is null)
		{
			Scope* s = allocate!Scope(semanticAllocator,
				withStatement.statementNoCaseNoDefault.startLocation,
				withStatement.statementNoCaseNoDefault.endLocation);
			s.parent = currentScope;
			currentScope.children.insert(s);
			currentScope = s;
			SemanticSymbol* symbol = allocateSemanticSymbol(WITH_SYMBOL_NAME,
				CompletionKind.withSymbol, symbolFile, s.startLocation, null);
			symbol.parent = currentSymbol;
			currentSymbol = symbol;
			populateInitializer(symbol, withStatement.expression, false);
			withStatement.accept(this);
			currentSymbol = currentSymbol.parent;
			currentSymbol.addChild(symbol);
			currentScope = currentScope.parent;
		}
		else
			withStatement.accept(this);
	}

	alias visit = ASTVisitor.visit;

	/// Module scope
	Scope* moduleScope;

	/// The module
	SemanticSymbol* rootSymbol;

	/// Allocator used for symbol allocation
	CAllocator symbolAllocator;

	/// Number of symbols allocated
	uint symbolsAllocated;

private:

	template visitEnumMember(T)
	{
		override void visit(const T member)
		{
//			Log.trace(__FUNCTION__, " ", typeof(member).stringof);
			SemanticSymbol* symbol = allocateSemanticSymbol(member.name.text,
				CompletionKind.enumMember, symbolFile, member.name.index, member.type);
			symbol.parent = currentSymbol;
			symbol.acSymbol.doc = internString(member.comment);
			currentSymbol.addChild(symbol);
		}
	}

	void visitAggregateDeclaration(AggType)(AggType dec, CompletionKind kind)
	{
//		Log.trace("visiting aggregate declaration ", dec.name.text);
		if (kind == CompletionKind.unionName && dec.name == tok!"")
		{
			dec.accept(this);
			return;
		}
		SemanticSymbol* symbol = allocateSemanticSymbol(dec.name.text,
			kind, symbolFile, dec.name.index);
		if (kind == CompletionKind.className)
			symbol.acSymbol.parts.insert(classSymbols[]);
		else
			symbol.acSymbol.parts.insert(aggregateSymbols[]);
		symbol.parent = currentSymbol;
		symbol.protection = protection;
		symbol.acSymbol.doc = internString(dec.comment);

		immutable size_t scopeBegin = dec.name.index + dec.name.text.length;
		static if (is (AggType == const(TemplateDeclaration)))
			immutable size_t scopeEnd = dec.endLocation;
		else
			immutable size_t scopeEnd = dec.structBody is null ? scopeBegin : dec.structBody.endLocation;
		Scope* s = allocate!Scope(semanticAllocator, scopeBegin, scopeEnd);
		s.parent = currentScope;
		currentScope.children.insert(s);
		currentScope = s;
		currentSymbol = symbol;
		processTemplateParameters(currentSymbol, dec.templateParameters);
		dec.accept(this);
		currentSymbol = symbol.parent;
		currentSymbol.addChild(symbol);
		currentScope = currentScope.parent;
	}

	void visitConstructor(size_t location, const Parameters parameters,
		const TemplateParameters templateParameters,
		const FunctionBody functionBody, string doc)
	{
		SemanticSymbol* symbol = allocateSemanticSymbol("*constructor*",
			CompletionKind.functionName, symbolFile, location);
		processParameters(symbol, null, "this", parameters, templateParameters);
		symbol.protection = protection;
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = internString(doc);
		currentSymbol.addChild(symbol);
		if (functionBody !is null)
		{
			Scope* s = createFunctionScope(functionBody, semanticAllocator,
				location + 4); // 4 == "this".length
			currentScope.children.insert(s);
			s.parent = currentScope;
			currentScope = s;
			currentSymbol = symbol;
			functionBody.accept(this);
			currentSymbol = symbol.parent;
			currentScope = s.parent;
		}
	}

	void visitDestructor(size_t location, const FunctionBody functionBody, string doc)
	{
		SemanticSymbol* symbol = allocateSemanticSymbol("~this",
			CompletionKind.functionName, symbolFile, location);
		symbol.acSymbol.callTip = "~this()";
		symbol.protection = protection;
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = internString(doc);
		currentSymbol.addChild(symbol);
		if (functionBody !is null)
		{
			Scope* s = createFunctionScope(functionBody, semanticAllocator,
				location + 4); // 4 == "this".length
			currentScope.children.insert(s);
			s.parent = currentScope;
			currentScope = s;
			currentSymbol = symbol;
			functionBody.accept(this);
			currentSymbol = symbol.parent;
			currentScope = s.parent;
		}
	}

	void processParameters(SemanticSymbol* symbol, const Type returnType,
		string functionName, const Parameters parameters,
		const TemplateParameters templateParameters)
	{
		processTemplateParameters(symbol, templateParameters);
		if (parameters !is null)
		{
			foreach (const Parameter p; parameters.parameters)
			{
				SemanticSymbol* parameter = allocateSemanticSymbol(
					p.name.text, CompletionKind.variableName, symbolFile,
					p.name.index, p.type);
				symbol.addChild(parameter);
				parameter.parent = symbol;
			}
			if (parameters.hasVarargs)
			{
				SemanticSymbol* argptr = allocateSemanticSymbol("_argptr",
					CompletionKind.variableName, null, size_t.max, argptrType);
				argptr.parent = symbol;
				symbol.addChild(argptr);

				SemanticSymbol* arguments = allocateSemanticSymbol("_arguments",
					CompletionKind.variableName, null, size_t.max, argumentsType);
				arguments.parent = symbol;
				symbol.addChild(arguments);
			}
		}
		symbol.acSymbol.callTip = formatCallTip(returnType, functionName,
			parameters, templateParameters);
	}

	void processTemplateParameters(SemanticSymbol* symbol, const TemplateParameters templateParameters)
	{
		if (templateParameters !is null && templateParameters.templateParameterList !is null)
		{
			foreach (const TemplateParameter p; templateParameters.templateParameterList.items)
			{
				string name;
				CompletionKind kind;
				size_t index;
				Rebindable!(const(Type)) type;
				if (p.templateAliasParameter !is null)
				{
					name = p.templateAliasParameter.identifier.text;
					kind = CompletionKind.aliasName;
					index = p.templateAliasParameter.identifier.index;
				}
				else if (p.templateTypeParameter !is null)
				{
					name = p.templateTypeParameter.identifier.text;
					kind = CompletionKind.aliasName;
					index = p.templateTypeParameter.identifier.index;
				}
				else if (p.templateValueParameter !is null)
				{
					name = p.templateValueParameter.identifier.text;
					kind = CompletionKind.variableName;
					index = p.templateValueParameter.identifier.index;
					type = p.templateValueParameter.type;
				}
				else
					continue;
				SemanticSymbol* templateParameter = allocateSemanticSymbol(name, kind,
					symbolFile, index, type);
				symbol.addChild(templateParameter);
				templateParameter.parent = symbol;
			}
		}
	}

	string formatCallTip(const Type returnType, string name,
		const Parameters parameters, const TemplateParameters templateParameters)
	{
		QuickAllocator!1024 q;
		auto app = Appender!(char, typeof(q), 1024)(q);
		scope(exit) q.deallocate(app.mem);
		if (returnType !is null)
		{
			app.formatNode(returnType);
			app.put(' ');
		}
		app.put(name);
		if (templateParameters !is null)
			app.formatNode(templateParameters);
		if (parameters is null)
			app.put("()");
		else
			app.formatNode(parameters);
		return internString(cast(string) app[]);
	}

	void populateInitializer(T)(SemanticSymbol* symbol, const T initializer,
		bool appendForeach = false)
	{
		auto visitor = scoped!InitializerVisitor(symbol, appendForeach);
		visitor.visit(initializer);
	}

	SemanticSymbol* allocateSemanticSymbol(string name, CompletionKind kind,
		string symbolFile, size_t location = 0, const Type type = null)
	in
	{
		assert (symbolAllocator !is null);
	}
	body
	{
		ACSymbol* acSymbol = allocate!ACSymbol(symbolAllocator, name, kind);
		acSymbol.location = location;
		acSymbol.symbolFile = symbolFile;
		symbolsAllocated++;
		return allocate!SemanticSymbol(semanticAllocator, acSymbol, type);
	}

	/// Current protection type
	IdType protection;

	/// Current scope
	Scope* currentScope;

	/// Current symbol
	SemanticSymbol* currentSymbol;

	/// Path to the file being converted
	string symbolFile;

	Module mod;

	CAllocator semanticAllocator;

	Rebindable!(const AssignExpression) feExpression;
}

void formatNode(A, T)(ref A appender, const T node)
{
	if (node is null)
		return;
	auto f = scoped!(Formatter!(A*))(&appender);
	f.format(node);
}

private:

Scope* createFunctionScope(const FunctionBody functionBody, CAllocator semanticAllocator,
	size_t scopeBegin)
{
	import std.algorithm : max;
	size_t scopeEnd = max(
		functionBody.inStatement is null ? 0 : functionBody.inStatement.blockStatement.endLocation,
		functionBody.outStatement is null ? 0 : functionBody.outStatement.blockStatement.endLocation,
		functionBody.blockStatement is null ? 0 : functionBody.blockStatement.endLocation,
		functionBody.bodyStatement is null ? 0 : functionBody.bodyStatement.blockStatement.endLocation);
	return allocate!Scope(semanticAllocator, scopeBegin, scopeEnd);
}

string[] iotcToStringArray(A)(ref A allocator, const IdentifierOrTemplateChain iotc)
{
	string[] retVal = cast(string[]) allocator.allocate((string[]).sizeof
		* iotc.identifiersOrTemplateInstances.length);
	foreach (i, ioti; iotc.identifiersOrTemplateInstances)
	{
		if (ioti.identifier != tok!"")
			retVal[i] = internString(ioti.identifier.text);
		else
			retVal[i] = internString(ioti.templateInstance.identifier.text);
	}
	return retVal;
}

static string convertChainToImportPath(const IdentifierChain ic)
{
	import std.path : dirSeparator;
	QuickAllocator!1024 q;
	auto app = Appender!(char, typeof(q), 1024)(q);
	scope(exit) q.deallocate(app.mem);
	foreach (i, ident; ic.identifiers)
	{
		app.append(ident.text);
		if (i + 1 < ic.identifiers.length)
			app.append(dirSeparator);
	}
	return internString(cast(string) app[]);
}

class InitializerVisitor : ASTVisitor
{
	this (SemanticSymbol* semanticSymbol, bool appendForeach = false)
	{
		this.semanticSymbol = semanticSymbol;
		this.appendForeach = appendForeach;
	}

	alias visit = ASTVisitor.visit;

	override void visit(const IdentifierOrTemplateInstance ioti)
	{
		if (on && ioti.identifier != tok!"")
			semanticSymbol.initializer.insert(ioti.identifier.text);
		ioti.accept(this);
	}

	override void visit(const PrimaryExpression primary)
	{
		// Add identifiers without processing. Convert literals to strings with
		// the prefix '*' so that that the third pass can tell the difference
		// between "int.abc" and "10.abc".
		if (on && primary.basicType != tok!"")
			semanticSymbol.initializer.insert(str(primary.basicType.type));
		if (on) switch (primary.primary.type)
		{
		case tok!"identifier":
			semanticSymbol.initializer.insert(primary.primary.text);
			break;
		case tok!"doubleLiteral":
			semanticSymbol.initializer.insert("*double");
			break;
		case tok!"floatLiteral":
			semanticSymbol.initializer.insert("*float");
			break;
		case tok!"idoubleLiteral":
			semanticSymbol.initializer.insert("*idouble");
			break;
		case tok!"ifloatLiteral":
			semanticSymbol.initializer.insert("*ifloat");
			break;
		case tok!"intLiteral":
			semanticSymbol.initializer.insert("*int");
			break;
		case tok!"longLiteral":
			semanticSymbol.initializer.insert("*long");
			break;
		case tok!"realLiteral":
			semanticSymbol.initializer.insert("*real");
			break;
		case tok!"irealLiteral":
			semanticSymbol.initializer.insert("*ireal");
			break;
		case tok!"uintLiteral":
			semanticSymbol.initializer.insert("*uint");
			break;
		case tok!"ulongLiteral":
			semanticSymbol.initializer.insert("*ulong");
			break;
		case tok!"characterLiteral":
			semanticSymbol.initializer.insert("*char");
			break;
		case tok!"dstringLiteral":
			semanticSymbol.initializer.insert("*dstring");
			break;
		case tok!"stringLiteral":
			semanticSymbol.initializer.insert("*string");
			break;
		case tok!"wstringLiteral":
			semanticSymbol.initializer.insert("*wstring");
			break;
		default:
			break;
		}
		primary.accept(this);
	}

	override void visit(const UnaryExpression unary)
	{
		unary.accept(this);
		if (unary.indexExpression)
			semanticSymbol.initializer.insert("[]");
	}

	override void visit(const ArgumentList) {}

	override void visit(const AssignExpression initializer)
	{
		on = true;
		initializer.accept(this);
		if (appendForeach)
			semanticSymbol.initializer.insert("foreach");
		on = false;
	}

	SemanticSymbol* semanticSymbol;
	bool on = false;
	const bool appendForeach;
}
