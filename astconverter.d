/*******************************************************************************
 * Authors: Brian Schott
 * Copyright: Brian Schott
 * Date: Sep 21 2013
 *
 * License:
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
 ******************************************************************************/

module astconverter;

import std.algorithm;
import std.array;
import std.conv;
import std.path;
import std.range;
import std.typecons;

import stdx.d.ast;
import stdx.d.lexer;
import stdx.d.parser;

import actypes;
import constants;
import messages;
import semantic;
import stupidlog;
import modulecache;

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
	this(Module mod, string symbolFile)
	{
		this.symbolFile = symbolFile;
		this.mod = mod;
	}

	void run()
	{
		visit(mod);
		mod = null;
	}

	override void visit(Unittest u)
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

	override void visit(Constructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, con.parameters, con.functionBody, con.comment);
	}

	override void visit(SharedStaticConstructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, null, con.functionBody, con.comment);
	}

	override void visit(StaticConstructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, null, con.functionBody, con.comment);
	}

	override void visit(Destructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.location, des.functionBody, des.comment);
	}

	override void visit(SharedStaticDestructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.location, des.functionBody, des.comment);
	}

	override void visit(StaticDestructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.location, des.functionBody, des.comment);
	}

	override void visit(FunctionDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		SemanticSymbol* symbol = new SemanticSymbol(getCached(dec.name.text),
			CompletionKind.functionName, symbolFile, dec.name.index);
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

	override void visit(ClassDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.className);
	}

	override void visit(TemplateDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.templateName);
	}

	override void visit(InterfaceDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.interfaceName);
	}

	override void visit(UnionDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.unionName);
	}

	override void visit(StructDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.structName);
	}

	override void visit(BaseClass bc)
	{
//		Log.trace(__FUNCTION__, " ", typeof(bc).stringof);
		currentSymbol.baseClasses ~= iotcToStringArray(bc.identifierOrTemplateChain);
	}

	override void visit(VariableDeclaration dec)
	{
		assert (currentSymbol);
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		Type t = dec.type;
		foreach (declarator; dec.declarators)
		{
			SemanticSymbol* symbol = new SemanticSymbol(
				getCached(declarator.name.text),
				CompletionKind.variableName,
				symbolFile,
				declarator.name.index);
			symbol.type = t;
			symbol.protection = protection;
			symbol.parent = currentSymbol;
			symbol.acSymbol.doc = dec.comment;
			currentSymbol.addChild(symbol);
		}
	}

	override void visit(AliasDeclaration aliasDeclaration)
	{
		if (aliasDeclaration.initializers.length == 0)
		{
			SemanticSymbol* symbol = new SemanticSymbol(
				getCached(aliasDeclaration.name.text),
				CompletionKind.aliasName,
				symbolFile,
				aliasDeclaration.name.index);
			symbol.type = aliasDeclaration.type;
			symbol.protection = protection;
			symbol.parent = currentSymbol;
			currentSymbol.addChild(symbol);
		}
		else
		{
			foreach (initializer; aliasDeclaration.initializers)
			{
				SemanticSymbol* symbol = new SemanticSymbol(
					getCached(initializer.name.text),
					CompletionKind.aliasName,
					symbolFile,
					initializer.name.index);
				symbol.type = initializer.type;
				symbol.protection = protection;
				symbol.parent = currentSymbol;
				currentSymbol.addChild(symbol);
			}
		}
	}

	override void visit(AliasThisDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		currentSymbol.aliasThis ~= getCached(dec.identifier.text);
	}

	override void visit(Declaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		if (dec.attributeDeclaration !is null
			&& isProtection(dec.attributeDeclaration.attribute.attribute))
		{
			protection = dec.attributeDeclaration.attribute.attribute;
			return;
		}
		IdType p = protection;
		foreach (Attribute attr; dec.attributes)
		{
			if (isProtection(attr.attribute))
				protection = attr.attribute;
		}
		dec.accept(this);
		protection = p;
	}

	override void visit(Module mod)
	{
//		Log.trace(__FUNCTION__, " ", typeof(mod).stringof);
//
		currentSymbol = new SemanticSymbol(null, CompletionKind.moduleName,
			symbolFile);
		rootSymbol = currentSymbol;
		currentScope = new Scope(0, size_t.max);
		moduleScope = currentScope;
		mod.accept(this);
	}

	override void visit(EnumDeclaration dec)
	{
		assert (currentSymbol);
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		SemanticSymbol* symbol = new SemanticSymbol(getCached(dec.name.text),
			CompletionKind.enumName, symbolFile, dec.name.index);
		symbol.type = dec.type;
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = dec.comment;
		currentSymbol = symbol;
		if (dec.enumBody !is null)
			dec.enumBody.accept(this);
		currentSymbol = symbol.parent;
		currentSymbol.addChild(symbol);
	}

	override void visit(EnumMember member)
	{
//		Log.trace(__FUNCTION__, " ", typeof(member).stringof);
		SemanticSymbol* symbol = new SemanticSymbol(getCached(member.name.text),
			CompletionKind.enumMember, symbolFile, member.name.index);
		symbol.type = member.type;
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = member.comment;
		currentSymbol.addChild(symbol);
	}

	override void visit(ModuleDeclaration moduleDeclaration)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		foreach (identifier; moduleDeclaration.moduleName.identifiers)
		{
			moduleName ~= getCached(identifier.text);
		}
	}

	// creates scopes for
	override void visit(StructBody structBody)
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

	override void visit(ImportDeclaration importDeclaration)
	{
//		Log.trace(__FUNCTION__, " ImportDeclaration");
		foreach (single; importDeclaration.singleImports.filter!(
			a => a !is null && a.identifierChain !is null))
		{
			ImportInformation info;
			info.importParts = single.identifierChain.identifiers.map!(a => a.text).array;
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
			.identifierChain.identifiers.map!(a => a.text).array;
		foreach (bind; importDeclaration.importBindings.importBinds)
		{
			Tuple!(string, string) bindTuple;
			bindTuple[0] = getCached(bind.left.text);
			bindTuple[1] = bind.right == tok!"" ? null : getCached(bind.right.text);
			info.importedSymbols ~= bindTuple;
		}
		info.isPublic = protection == tok!"public";
		currentScope.importInformation ~= info;
	}

	// Create scope for block statements
	override void visit(BlockStatement blockStatement)
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

	override void visit(VersionCondition versionCondition)
	{
		// TODO: This is a bit of a hack
		if (predefinedVersions.canFind(versionCondition.token.text))
			versionCondition.accept(this);
	}

	alias visit = ASTVisitor.visit;

private:

	void visitAggregateDeclaration(AggType)(AggType dec, CompletionKind kind)
	{
//		Log.trace("visiting aggregate declaration ", dec.name.text);
		SemanticSymbol* symbol = new SemanticSymbol(getCached(dec.name.text),
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

	void visitConstructor(size_t location, Parameters parameters,
		FunctionBody functionBody, string doc)
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

	void visitDestructor(size_t location, FunctionBody functionBody, string doc)
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

	void processParameters(SemanticSymbol* symbol, Type returnType,
		string functionName, Parameters parameters, string doc) const
	{
		if (parameters !is null)
		{
			foreach (Parameter p; parameters.parameters)
			{
				SemanticSymbol* parameter = new SemanticSymbol(getCached(p.name.text),
					CompletionKind.variableName, symbolFile, size_t.max);
				parameter.type = p.type;
				symbol.addChild(parameter);
				parameter.parent = symbol;
			}
			if (parameters.hasVarargs)
			{
				SemanticSymbol* argptr = new SemanticSymbol("_argptr",
					CompletionKind.variableName, null, size_t.max);
				argptr.type = argptrType;
				argptr.parent = symbol;
				symbol.addChild(argptr);

				SemanticSymbol* arguments = new SemanticSymbol("_arguments",
					CompletionKind.variableName, null, size_t.max);
				arguments.type = argumentsType;
				arguments.parent = symbol;
				symbol.addChild(arguments);
			}
		}
		symbol.acSymbol.callTip = formatCallTip(returnType, functionName,
			parameters, doc);
		symbol.type = returnType;
	}

	static string formatCallTip(Type returnType, string name, Parameters parameters,
		string doc = null)
	{
		string parameterString = parameters is null ? "()"
			: formatNode(parameters);
		if (returnType is null)
			return "%s%s".format(name, parameterString);
		return "%s %s%s".format(formatNode(returnType), name, parameterString);
	}

	/// Current protection type
	IdType protection;

	/// Current symbol
	SemanticSymbol* currentSymbol;

	/// The module
	SemanticSymbol* rootSymbol;

	/// Package and module name
	string[] moduleName;

	/// Current scope
	Scope* currentScope;

	/// Module scope
	Scope* moduleScope;

	/// Path to the file being converted
	string symbolFile;

	Module mod;
}

/**
 * Second pass handles the following:
 * $(UL
 *     $(LI Import statements)
 *     $(LI assigning symbols to scopes)
 * )
 */
struct SecondPass
{
public:

	this(SemanticSymbol* rootSymbol, Scope* moduleScope)
	{
		this.rootSymbol = rootSymbol;
		this.moduleScope = moduleScope;
	}

	void run()
	{
		assignToScopes(rootSymbol.acSymbol);
		resolveImports(moduleScope);
	}

private:

	void assignToScopes(ACSymbol* currentSymbol)
	{
		Scope* s = moduleScope.getScopeByCursor(currentSymbol.location);
		s.symbols.insert(currentSymbol);
		foreach (part; currentSymbol.parts[])
			assignToScopes(part);
	}

	// This method is really ugly due to the casts...
	static ACSymbol* createImportSymbols(ImportInformation info,
		Scope* currentScope)
	{
		immutable string firstPart = info.importParts[0];
		ACSymbol*[] symbols = currentScope.getSymbolsByName(firstPart);
		immutable bool found = symbols.length > 0;
		ACSymbol* firstSymbol = found
			? symbols[0] : new ACSymbol(firstPart, CompletionKind.packageName);
		if (!found)
		{
			currentScope.symbols.insert(firstSymbol);
		}
		ACSymbol* currentSymbol = cast(ACSymbol*) firstSymbol;
		foreach (size_t i, string importPart; info.importParts[1 .. $])
		{
			symbols = currentSymbol.getPartsByName(importPart);
			ACSymbol* s = symbols.length > 0
				? cast(ACSymbol*) symbols[0] : new ACSymbol(importPart, CompletionKind.packageName);
			currentSymbol.parts.insert(s);
			currentSymbol = s;
		}
		currentSymbol.kind = CompletionKind.moduleName;
		return currentSymbol;
	}

	void resolveImports(Scope* currentScope)
	{
		foreach (importInfo; currentScope.importInformation)
		{
			ACSymbol*[] symbols = ModuleCache.getSymbolsInModule(
				ModuleCache.resolveImportLoctation(importInfo.modulePath));
			ACSymbol* moduleSymbol = createImportSymbols(importInfo, currentScope);
			currentScope.symbols.insert(moduleSymbol);
			currentScope.symbols.insert(symbols);
			if (importInfo.importedSymbols.length == 0)
			{
				if (importInfo.isPublic && currentScope.parent is null)
				{
					rootSymbol.acSymbol.parts.insert(symbols);
				}
				continue;
			}
			symbolLoop: foreach (symbol; symbols)
			{
				foreach (tup; importInfo.importedSymbols)
				{
					if (tup[0] != symbol.name)
						continue symbolLoop;
					if (tup[1] !is null)
					{
						ACSymbol* s = new ACSymbol(tup[1],
							symbol.kind, symbol.type);
						// TODO: Compiler gets confused here, so cast the types.
						s.parts = cast(typeof(s.parts)) symbol.parts;
						// TODO: Re-format callTip with new name?
						s.callTip = symbol.callTip;
						s.doc = symbol.doc;
						s.qualifier = symbol.qualifier;
						s.location = symbol.location;
						s.symbolFile = symbol.symbolFile;
						currentScope.symbols.insert(s);
						moduleSymbol.parts.insert(s);
						if (importInfo.isPublic && currentScope.parent is null)
							rootSymbol.acSymbol.parts.insert(s);
					}
					else
					{
						moduleSymbol.parts.insert(symbol);
						currentScope.symbols.insert(symbol);
						if (importInfo.isPublic && currentScope.parent is null)
							rootSymbol.acSymbol.parts.insert(symbol);
					}
				}
			}
		}
		foreach (childScope; currentScope.children)
			resolveImports(childScope);
	}

	SemanticSymbol* rootSymbol;
	Scope* moduleScope;
}

/**
 * Third pass handles the following:
 * $(UL
 *      $(LI types)
 *      $(LI base classes)
 *      $(LI mixin templates)
 *      $(LI alias this)
 *      $(LI alias declarations)
 * )
 */
struct ThirdPass
{
public:
	this(SemanticSymbol* rootSymbol, Scope* moduleScope) pure
	{
		this.rootSymbol = rootSymbol;
		this.moduleScope = moduleScope;
	}

	void run()
	{
		thirdPass(rootSymbol);
	}

private:

	void thirdPass(SemanticSymbol* currentSymbol)
	{
//		Log.trace("third pass on ", currentSymbol.acSymbol.name);
		with (CompletionKind) final switch (currentSymbol.acSymbol.kind)
		{
		case className:
		case interfaceName:
			resolveInheritance(currentSymbol);
			goto case structName;
		case structName:
		case unionName:
			resolveAliasThis(currentSymbol);
			resolveMixinTemplates(currentSymbol);
			break;
		case variableName:
		case memberVariableName:
		case functionName:
		case aliasName:
			ACSymbol* t = resolveType(currentSymbol.type,
				currentSymbol.acSymbol.location);
			while (t !is null && t.kind == CompletionKind.aliasName)
				t = t.type;
			currentSymbol.acSymbol.type = t;
			break;
		case enumName:
		case keyword:
		case enumMember:
		case packageName:
		case moduleName:
		case dummy:
		case array:
		case assocArray:
		case templateName:
		case mixinTemplateName:
			break;
		}
		foreach (child; currentSymbol.children)
		{
			thirdPass(child);
		}
	}

	void resolveInheritance(SemanticSymbol* currentSymbol)
	{
//		Log.trace("Resolving inheritance for ", currentSymbol.acSymbol.name);
		outer: foreach (string[] base; currentSymbol.baseClasses)
		{
			ACSymbol* baseClass;
			if (base.length == 0)
				continue;
			auto symbols = moduleScope.getSymbolsByNameAndCursor(
				base[0], currentSymbol.acSymbol.location);
			if (symbols.length == 0)
				continue;
			baseClass = symbols[0];
			foreach (part; base[1..$])
			{
				symbols = baseClass.getPartsByName(part);
				if (symbols.length == 0)
					continue outer;
				baseClass = symbols[0];
			}
			currentSymbol.acSymbol.parts.insert(baseClass.parts[]);
		}
	}

	void resolveAliasThis(SemanticSymbol* currentSymbol)
	{
		// TODO:
	}

	void resolveMixinTemplates(SemanticSymbol* currentSymbol)
	{
		// TODO:
	}

	ACSymbol* resolveType(Type t, size_t location)
	{
		if (t is null) return null;
		if (t.type2 is null) return null;
		ACSymbol* s;
		if (t.type2.builtinType != tok!"")
			s = convertBuiltinType(t.type2);
		else if (t.type2.typeConstructor != tok!"")
			s = resolveType(t.type2.type, location);
		else if (t.type2.symbol !is null)
		{
			// TODO: global scoped symbol handling
			string[] symbolParts = expandSymbol(
				t.type2.symbol.identifierOrTemplateChain);
			auto symbols = moduleScope.getSymbolsByNameAndCursor(
				symbolParts[0], location);
			if (symbols.length == 0)
				goto resolveSuffixes;
			s = symbols[0];
			foreach (symbolPart; symbolParts[1..$])
			{
				auto parts = s.getPartsByName(symbolPart);
				if (parts.length == 0)
					goto resolveSuffixes;
				s = parts[0];
			}
		}
	resolveSuffixes:
		foreach (suffix; t.typeSuffixes)
			s = processSuffix(s, suffix);
		return s;
	}

	static string[] expandSymbol(const IdentifierOrTemplateChain chain)
	{
		string[] strings = new string[chain.identifiersOrTemplateInstances.length];
		for (size_t i = 0; i != chain.identifiersOrTemplateInstances.length; ++i)
		{
			auto identOrTemplate = chain.identifiersOrTemplateInstances[i];
			if (identOrTemplate is null)
				continue;
			strings[i] = getCached(identOrTemplate.templateInstance is null ?
				identOrTemplate.identifier.text
				: identOrTemplate.templateInstance.identifier.text);
		}
		return strings;
	}

	static ACSymbol* processSuffix(ACSymbol* symbol, const TypeSuffix suffix)
	{
		import std.container;
		if (suffix.star)
			return symbol;
		if (suffix.array || suffix.type)
		{
			ACSymbol* s = new ACSymbol(null);
			s.parts = new RedBlackTree!(ACSymbol*, comparitor, true);
			s.parts.insert(suffix.array ? (cast() arraySymbols)[]
				: (cast() assocArraySymbols)[]);
			s.type = symbol;
			s.qualifier = suffix.array ? SymbolQualifier.array : SymbolQualifier.assocArray;
			return s;
		}
		if (suffix.parameters)
		{
			ACSymbol* s = new ACSymbol(null);
			s.type = symbol;
			s.qualifier = SymbolQualifier.func;
			s.callTip = suffix.delegateOrFunction.text ~ formatNode(suffix.parameters);
			return s;
		}
		return null;
	}

	static ACSymbol* convertBuiltinType(const Type2 type2)
	{
		string stringRepresentation = str(type2.builtinType);
		if (stringRepresentation is null) return null;
		// TODO: Make this use binary search instead
		auto t = cast() builtinSymbols;
		ACSymbol s = ACSymbol(stringRepresentation);
		return t.equalRange(&s).front();
	}

	SemanticSymbol* rootSymbol;
	Scope* moduleScope;
}

ACSymbol*[] convertAstToSymbols(const(Token)[] tokens, string symbolFile)
{
	Module m = parseModuleSimple(tokens, symbolFile);

	FirstPass first = new FirstPass(m, symbolFile);
	first.run();

	SecondPass second = SecondPass(first.rootSymbol, first.moduleScope);
	second.run();

	ThirdPass third = ThirdPass(second.rootSymbol, second.moduleScope);
	third.run();

	return third.rootSymbol.acSymbol.parts.array();
}

const(Scope)* generateAutocompleteTrees(const(Token)[] tokens, string symbolFile)
{
	Module m = parseModule(tokens, "editor buffer", &doesNothing);

	FirstPass first = new FirstPass(m, symbolFile);
	first.run();

	SecondPass second = SecondPass(first.rootSymbol, first.currentScope);
	second.run();

	ThirdPass third = ThirdPass(second.rootSymbol, second.moduleScope);
	third.run();

	return cast(typeof(return)) third.moduleScope;
}

private:

Module parseModuleSimple(const(Token)[] tokens, string fileName)
{
	auto parser = new SimpleParser();
	parser.fileName = fileName;
	parser.tokens = tokens;
	parser.messageFunction = &doesNothing;
	auto mod = parser.parseModule();
	return mod;
}

class SimpleParser : Parser
{
	override Unittest parseUnittest()
	{
		expect(tok!"unittest");
		skipBraces();
		return null;
	}

	override FunctionBody parseFunctionBody()
	{
		if (currentIs(tok!";"))
			advance();
		else if (currentIs(tok!"{"))
			skipBraces();
		else
		{
			if (currentIs(tok!"in"))
			{
				advance();
				if (currentIs(tok!"{"))
					skipBraces();
				if (currentIs(tok!"out"))
				{
					advance();
					if (currentIs(tok!"("))
						skipParens();
					if (currentIs(tok!"{"))
						skipBraces();
				}
			}
			else if (currentIs(tok!"out"))
			{
				advance();
				if (currentIs(tok!"("))
					skipParens();
				if (currentIs(tok!"{"))
					skipBraces();
				if (currentIs(tok!"in"))
				{
					advance();
					if (currentIs(tok!"{"))
						skipBraces();
				}
			}
			expect(tok!"body");
			if (currentIs(tok!"{"))
				skipBraces();
		}
		return null;
	}
}

string[] iotcToStringArray(const IdentifierOrTemplateChain iotc)
{
	string[] parts;
	foreach (ioti; iotc.identifiersOrTemplateInstances)
	{
		if (ioti.identifier != tok!"")
			parts ~= getCached(ioti.identifier.text);
		else
			parts ~= getCached(ioti.templateInstance.identifier.text);
	}
	return parts;
}

private static string convertChainToImportPath(IdentifierChain chain)
{
	return to!string(chain.identifiers.map!(a => a.text).join(dirSeparator).array);
}

version(unittest) Module parseTestCode(string code)
{
	LexerConfig config;
	const(Token)[] tokens = byToken(cast(ubyte[]) code, config).array();
	Module m = parseModule(tokens, "unittest");
	return m;
}

string formatNode(T)(T node)
{
	if (node is null) return "";
	import formatter;
	auto app = appender!(char[])();
	auto f = new Formatter!(typeof(app))(app);
	f.format(node);
	return to!string(app.data);
}

private void doesNothing(string a, size_t b, size_t c, string d, bool e) {}

/**
 * Dummy doc comment for getCached
 */
string getCached(string s)
{
	return s.length == 0 ? ""
		: ModuleCache.stringCache.cacheGet(cast(const(ubyte)[]) s);
}
