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
import modulecache; // circular import

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
		visitConstructor(con.location, con.parameters, con.functionBody);
	}

	override void visit(SharedStaticConstructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, null, con.functionBody);
	}

	override void visit(StaticConstructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, null, con.functionBody);
	}

	override void visit(Destructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.location, des.functionBody);
	}

	override void visit(SharedStaticDestructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.location, des.functionBody);
	}

	override void visit(StaticDestructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.location, des.functionBody);
	}

	override void visit(FunctionDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		SemanticSymbol* symbol = new SemanticSymbol(dec.name.value.dup,
			CompletionKind.functionName, symbolFile, dec.name.startIndex);
		processParameters(symbol, dec.returnType, symbol.acSymbol.name,
			dec.parameters);
		symbol.protection = protection;
		symbol.parent = currentSymbol;
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
				declarator.name.value.dup,
				CompletionKind.variableName,
				symbolFile,
				declarator.name.startIndex);
			symbol.type = t;
			symbol.protection = protection;
			symbol.parent = currentSymbol;
			currentSymbol.addChild(symbol);
		}
	}

	override void visit(AliasDeclaration aliasDeclaration)
	{
		if (aliasDeclaration.initializers.length == 0)
		{
			SemanticSymbol* symbol = new SemanticSymbol(
				aliasDeclaration.name.value.dup,
				CompletionKind.aliasName,
				symbolFile,
				aliasDeclaration.name.startIndex);
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
					initializer.name.value.dup,
					CompletionKind.aliasName,
					symbolFile,
					initializer.name.startIndex);
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
		currentSymbol.aliasThis ~= dec.identifier.value.dup;
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
		TokenType p = protection;
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

		currentScope = new Scope();
		currentScope.startLocation = 0;
		currentScope.endLocation = size_t.max;
		moduleScope = currentScope;

		mod.accept(this);
	}

	override void visit(EnumDeclaration dec)
	{
		assert (currentSymbol);
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		SemanticSymbol* symbol = new SemanticSymbol(dec.name.value.dup,
			CompletionKind.enumName, symbolFile, dec.name.startIndex);
		symbol.type = dec.type;
		symbol.parent = currentSymbol;
		currentSymbol = symbol;
		if (dec.enumBody !is null)
			dec.enumBody.accept(this);
		currentSymbol = symbol.parent;
		currentSymbol.addChild(symbol);
	}

	override void visit(EnumMember member)
	{
//		Log.trace(__FUNCTION__, " ", typeof(member).stringof);
		SemanticSymbol* symbol = new SemanticSymbol(member.name.value.dup,
			CompletionKind.enumMember, symbolFile, member.name.startIndex);
		symbol.type = member.type;
		symbol.parent = currentSymbol;
		currentSymbol.addChild(symbol);
	}

	override void visit(ModuleDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		foreach (Token t; dec.moduleName.identifiers)
			moduleName ~= t.value.dup;
	}

	// creates scopes for
	override void visit(StructBody structBody)
	{
//		Log.trace(__FUNCTION__, " ", typeof(structBody).stringof);
		Scope* s = new Scope;
		s.startLocation = structBody.startLocation;
		s.endLocation = structBody.endLocation;
//		Log.trace("Added scope ", s.startLocation, " ", s.endLocation);

		ACSymbol* thisSymbol = new ACSymbol("this", CompletionKind.variableName,
			currentSymbol.acSymbol);
		thisSymbol.location = s.startLocation;
		thisSymbol.symbolFile = symbolFile;
		currentSymbol.acSymbol.parts ~= thisSymbol;

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
			info.modulePath = convertChainToImportPath(single.identifierChain);
			info.isPublic = protection == TokenType.public_;
			currentScope.importInformation ~= info;
		}
		if (importDeclaration.importBindings is null) return;
		if (importDeclaration.importBindings.singleImport.identifierChain is null) return;
		ImportInformation info;
		info.modulePath = convertChainToImportPath(
			importDeclaration.importBindings.singleImport.identifierChain);
		foreach (bind; importDeclaration.importBindings.importBinds)
		{
			Tuple!(string, string) bindTuple;
			bindTuple[0] = bind.left.value.dup;
			bindTuple[1] = bind.right == TokenType.invalid ? null : bind.right.value.dup;
			info.importedSymbols ~= bindTuple;
		}
		info.isPublic = protection == TokenType.public_;
		currentScope.importInformation ~= info;
	}

	// Create scope for block statements
	override void visit(BlockStatement blockStatement)
	{
//		Log.trace(__FUNCTION__, " ", typeof(blockStatement).stringof);
		Scope* s = new Scope;
		s.parent = currentScope;
		currentScope.children ~= s;
		s.startLocation = blockStatement.startLocation;
		s.endLocation = blockStatement.endLocation;

		if (currentSymbol.acSymbol.kind == CompletionKind.functionName)
		{
			foreach (child; currentSymbol.children)
			{
				child.acSymbol.location = s.startLocation + 1;
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
		if (predefinedVersions.canFind(versionCondition.token.value))
			versionCondition.accept(this);
	}

	alias ASTVisitor.visit visit;

private:

	void visitAggregateDeclaration(AggType)(AggType dec, CompletionKind kind)
	{
//		Log.trace("visiting aggregate declaration ", dec.name.value);
		SemanticSymbol* symbol = new SemanticSymbol(dec.name.value.dup,
			kind, symbolFile, dec.name.startIndex);
		symbol.acSymbol.parts ~= classSymbols;
		symbol.parent = currentSymbol;
		symbol.protection = protection;
		currentSymbol = symbol;
		dec.accept(this);
		currentSymbol = symbol.parent;
		currentSymbol.addChild(symbol);
	}

	void visitConstructor(size_t location, Parameters parameters,
		FunctionBody functionBody)
	{
		SemanticSymbol* symbol = new SemanticSymbol("*constructor*",
			CompletionKind.functionName, symbolFile, location);
		processParameters(symbol, null, "this", parameters);
		symbol.protection = protection;
		symbol.parent = currentSymbol;
		currentSymbol.addChild(symbol);
		if (functionBody !is null)
		{
			currentSymbol = symbol;
			functionBody.accept(this);
			currentSymbol = symbol.parent;
		}
	}

	void visitDestructor(size_t location, FunctionBody functionBody)
	{
		SemanticSymbol* symbol = new SemanticSymbol("~this",
			CompletionKind.functionName, symbolFile, location);
		symbol.acSymbol.callTip = "~this()";
		symbol.protection = protection;
		symbol.parent = currentSymbol;
		currentSymbol.addChild(symbol);
		if (functionBody !is null)
		{
			currentSymbol = symbol;
			functionBody.accept(this);
			currentSymbol = symbol.parent;
		}
	}

	void processParameters(SemanticSymbol* symbol, Type returnType,
		string functionName, Parameters parameters) const
	{
		if (parameters !is null)
		{
			foreach (Parameter p; parameters.parameters)
			{
				SemanticSymbol* parameter = new SemanticSymbol(p.name.value.dup,
					CompletionKind.variableName, symbolFile, p.name.startIndex);
				parameter.type = p.type;
				symbol.addChild(parameter);
				parameter.parent = symbol;
			}
			if (parameters.hasVarargs)
			{
				SemanticSymbol* argptr = new SemanticSymbol("_argptr",
					CompletionKind.variableName, null, 0);
				argptr.type = argptrType;
				argptr.parent = symbol;
				symbol.addChild(argptr);

				SemanticSymbol* arguments = new SemanticSymbol("_arguments",
					CompletionKind.variableName, null, 0);
				arguments.type = argumentsType;
				arguments.parent = symbol;
				symbol.addChild(arguments);
			}
		}
		symbol.acSymbol.callTip = formatCallTip(returnType, functionName,
			parameters);
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
	TokenType protection;

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

	void assignToScopes(const(ACSymbol)* currentSymbol)
	{
		moduleScope.getScopeByCursor(currentSymbol.location).symbols
			~= currentSymbol;
		foreach (part; currentSymbol.parts)
			assignToScopes(part);
	}

	void resolveImports(Scope* currentScope)
	{
		foreach (importInfo; currentScope.importInformation)
		{
			auto symbols = ModuleCache.getSymbolsInModule(
				ModuleCache.resolveImportLoctation(importInfo.modulePath));
			if (importInfo.importedSymbols.length == 0)
			{
				currentScope.symbols ~= symbols;
				if (importInfo.isPublic && currentScope.parent is null)
				{
					rootSymbol.acSymbol.parts ~= symbols;
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
						s.qualifier = symbol.qualifier;
						s.location = symbol.location;
						s.symbolFile = symbol.symbolFile;
						currentScope.symbols ~= s;
						if (importInfo.isPublic && currentScope.parent is null)
							rootSymbol.acSymbol.parts ~= s;
					}
					else
					{
						currentScope.symbols ~= symbol;
						if (importInfo.isPublic && currentScope.parent is null)
							rootSymbol.acSymbol.parts ~= symbol;
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
			const(ACSymbol)* t = resolveType(currentSymbol.type,
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
			thirdPass(child);
	}

	void resolveInheritance(SemanticSymbol* currentSymbol)
	{
//		Log.trace("Resolving inheritance for ", currentSymbol.acSymbol.name);
		outer: foreach (string[] base; currentSymbol.baseClasses)
		{
			const(ACSymbol)* baseClass;
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
			currentSymbol.acSymbol.parts ~= baseClass.parts;
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

	const(ACSymbol)* resolveType(Type t, size_t location)
	{
		if (t is null) return null;
		if (t.type2 is null) return null;
		const(ACSymbol)* s;
		if (t.type2.builtinType != TokenType.invalid)
			s = convertBuiltinType(t.type2);
		else if (t.type2.typeConstructor != TokenType.invalid)
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

	static string[] expandSymbol(const IdentifierOrTemplateChain chain) pure
	{
		string[] strings = new string[chain.identifiersOrTemplateInstances.length];
		for (size_t i = 0; i != chain.identifiersOrTemplateInstances.length; ++i)
		{
			auto identOrTemplate = chain.identifiersOrTemplateInstances[i];
			if (identOrTemplate is null)
				continue;
			strings[i] = identOrTemplate.templateInstance is null ?
				identOrTemplate.identifier.value.dup
				: identOrTemplate.identifier.value.dup;
		}
		return strings;
	}

	static const(ACSymbol)* processSuffix(const(ACSymbol)* symbol, const TypeSuffix suffix)
	{
		if (suffix.star)
			return symbol;
		if (suffix.array || suffix.type)
		{
			ACSymbol* s = new ACSymbol;
			s.parts = suffix.array ? arraySymbols : assocArraySymbols;
			s.type = symbol;
			s.qualifier = suffix.array ? SymbolQualifier.array : SymbolQualifier.assocArray;
			return s;
		}
		if (suffix.parameters)
		{
			ACSymbol* s = new ACSymbol;
			s.type = symbol;
			s.qualifier = SymbolQualifier.func;
			s.callTip = suffix.delegateOrFunction.value ~ formatNode(suffix.parameters);
			return s;
		}
		return null;
	}

	static const(ACSymbol)* convertBuiltinType(const Type2 type2)
	{
		string stringRepresentation = getTokenValue(type2.builtinType);
		if (stringRepresentation is null) return null;
		// TODO: Make this use binary search instead
		foreach (s; builtinSymbols)
			if (s.name == stringRepresentation)
				return s;
		return null;
	}

	SemanticSymbol* rootSymbol;
	Scope* moduleScope;
}

const(ACSymbol)*[] convertAstToSymbols(const(Token)[] tokens, string symbolFile)
{
	Module m = parseModuleSimple(tokens, symbolFile);

	FirstPass first = new FirstPass(m, symbolFile);
	first.run();

	SecondPass second = SecondPass(first.rootSymbol, first.moduleScope);
	second.run();

	ThirdPass third = ThirdPass(second.rootSymbol, second.moduleScope);
	third.run();

	return cast(typeof(return)) third.rootSymbol.acSymbol.parts;
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
		expect(TokenType.unittest_);
		skipBraces();
		return null;
	}

	override FunctionBody parseFunctionBody()
	{
		if (currentIs(TokenType.semicolon))
			advance();
		else if (currentIs(TokenType.lBrace))
			skipBraces();
		else
		{
			if (currentIs(TokenType.in_))
			{
				advance();
				skipBraces();
				if (currentIs(TokenType.out_))
				{
					advance();
					if (currentIs(TokenType.lParen))
						skipParens();
					skipBraces();
				}
			}
			else if (currentIs(TokenType.out_))
			{
				advance();
				if (currentIs(TokenType.lParen))
					skipParens();
				skipBraces();
				if (currentIs(TokenType.in_))
				{
					advance();
					skipBraces();
				}
			}
			expect(TokenType.body_);
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
		if (ioti.identifier != TokenType.invalid)
			parts ~= ioti.identifier.value.dup;
		else
			parts ~= ioti.templateInstance.identifier.value.dup;
	}
	return parts;
}

private static string convertChainToImportPath(IdentifierChain chain)
{
	return to!string(chain.identifiers.map!(a => a.value).join(dirSeparator).array);
}

version(unittest) Module parseTestCode(string code)
{
	LexerConfig config;
	const(Token)[] tokens = byToken(cast(ubyte[]) code, config);
	Parser p = new Parser;
	p.fileName = "unittest";
	p.tokens = tokens;
	Module m = p.parseModule();
	assert (p.errorCount == 0);
	assert (p.warningCount == 0);
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

private void doesNothing(string a, int b, int c, string d) {}
