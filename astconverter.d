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

/**
 * AST conversion takes place in several steps
 * 1. AST is converted to a tree of SemanicSymbols, a tree of ACSymbols, and a
 * tree of scopes. The following fields are set on the symbols:
 *     * name
 *     * location
 *     * alias this
 *     * base class names
 *     * protection level
 *     * symbol kind
 *     * function call tip
 *     * symbol file path
 * Import statements are recorded in the scope tree.
 * 2. Scope tree is traversed and all imports are resolved by adding appropriate
 * ACSymbol instances.
 * 3. Semantic symbol tree is traversed
 *     * types are resolved
 *     * base classes are resolved
 *     * mixin templates are resolved
 *     * alias this is resolved
 */

module astconverter;

import std.array;
import std.conv;
import std.range;
import std.algorithm;

import stdx.d.ast;
import stdx.d.lexer;
import stdx.d.parser;

import actypes;
import messages;
import semantic;
import stupidlog;

class FirstPass : ASTVisitor
{
    override void visit(Constructor con)
    {
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
        visitFunctionDeclaration(con);
    }

    override void visit(SharedStaticConstructor con)
    {
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
        visitFunctionDeclaration(con);
    }

    override void visit(StaticConstructor con)
    {
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
        visitFunctionDeclaration(con);
    }

    override void visit(Destructor des)
    {
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
        visitFunctionDeclaration(des);
    }

    override void visit(SharedStaticDestructor des)
    {
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
        visitFunctionDeclaration(des);
    }

    override void visit(StaticDestructor des)
    {
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
        visitFunctionDeclaration(des);
    }

	override void visit(FunctionDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
        visitFunctionDeclaration(dec);
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
			SemanticSymbol* symbol = new SemanticSymbol;
			symbol.acSymbol.type = t;
			symbol.kind = CompletionKind.variableName;
			symbol.name = declarator.name.value.dup;
			symbol.location = declarator.name.startIndex;
			symbol.protection = protection;
			symbol.parent = currentSymbol;
			currentSymbol.addChild(symbol);
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
				p = attr.attribute;
		}
		dec.accept(this);
		protection = p;
	}

	override void visit(Module mod)
	{
//		Log.trace(__FUNCTION__, " ", typeof(mod).stringof);
		rootSymbol = new SemanticSymbol;
		rootSymbol.kind = CompletionKind.moduleName;
		rootSymbol.startLocation = 0;
		rootSymbol.endLocation = size_t.max;
		currentSymbol = rootSymbol;
		currentScope = new Scope();
		currentScope.startLocation = 0;
		currentScope.endLocation = size_t.max;
		mod.accept(this);
	}

    override void visit(EnumDeclaration dec)
    {
		assert (currentSymbol);
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
        SemanticSymbol* symbol = new SemanticSymbol;
        symbol.name = dec.name.value.dup;
        symbol.location = dec.name.startIndex;
        symbol.kind = CompletionKind.enumName;
        symbol.type = dec.type;
        symbol.parent = currentSymbol;
        currentSymbol = symbol;
        if (dec.enumBody !is null)
            dec.enumBody.accept(this);
        currentSymbol = symbol.parent;
        currentSymbol.children ~= symbol;
    }

    override void visit(EnumMember member)
    {
//		Log.trace(__FUNCTION__, " ", typeof(member).stringof);
        SemanticSymbol* symbol = new SemanticSymbol;
		symbol.kind = CompletionKind.enumMember;
        symbol.name = member.name.value.dup;
		symbol.location = member.name.startIndex;
        symbol.type = member.type;
        symbol.parent = currentSymbol;
        currentSymbol.children ~= symbol;
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
		s.parent = currentScope;
        currentScope = s;
        foreach (dec; structBody.declarations)
            visit(dec);
        currentScope = s.parent;
		currentScope.children ~= s;
	}

	// Create scope for block statements
	override void visit(BlockStatement blockStatement)
	{
//		Log.trace(__FUNCTION__, " ", typeof(blockStatement).stringof);
		Scope* s = new Scope;
		s.startLocation = blockStatement.startLocation;
		s.endLocation = blockStatement.endLocation;

		if (currentSymbol.kind == CompletionKind.functionName)
		{
			foreach (child; currentSymbol.children)
			{
//				Log.trace("Setting ", child.name, " location");
				child.location = s.startLocation + 1;
			}
		}
//		Log.trace("Added scope ", s.startLocation, " ", s.endLocation);
		s.parent = currentScope;
		if (blockStatement.declarationsAndStatements !is null)
		{
			currentScope = s;
			visit (blockStatement.declarationsAndStatements);
			currentScope = s.parent;
		}
		currentScope.children ~= s;
	}

	alias ASTVisitor.visit visit;

private:

	void visitAggregateDeclaration(AggType)(AggType dec, CompletionKind kind)
	{
		SemanticSymbol* symbol = new SemanticSymbol;
//		Log.trace("visiting aggregate declaration ", dec.name.value);
		symbol.name = dec.name.value.dup;
		symbol.location = dec.name.startIndex;
		symbol.kind = kind;
		symbol.parent = currentSymbol;
		symbol.protection = protection;
		currentSymbol = symbol;
		dec.accept(this);
		currentSymbol = symbol.parent;
		currentSymbol.children ~= symbol;
	}

	void visitFunctionDeclaration(DeclarationType)(DeclarationType dec)
    {
        SemanticSymbol* symbol = new SemanticSymbol;

        static if (is (DeclarationType == FunctionDeclaration))
        {
            symbol.name = dec.name.value.dup;
            symbol.location = dec.name.startIndex;
        }
        else static if (is (DeclarationType == Destructor)
            || is (DeclarationType == StaticDestructor)
            || is (DeclarationType == SharedStaticDestructor))
        {
            symbol.name = "*destructor*";
            symbol.location = dec.location;
        }
        else
        {
            symbol.name = "*constructor*";
            symbol.location = dec.location;
        }

        static if (is (DeclarationType == Destructor)
            || is (DeclarationType == StaticDestructor)
            || is (DeclarationType == SharedStaticDestructor))
        {
            symbol.callTip = "~this()";
        }
        else static if (is (DeclarationType == StaticConstructor)
            || is (DeclarationType == SharedStaticConstructor))
        {
            symbol.callTip = "this()";
        }
        else
        {
            string parameterString;
            if (dec.parameters !is null)
            {
                parameterString = formatNode(dec.parameters);
                foreach (Parameter p; dec.parameters.parameters)
                {
                    SemanticSymbol* parameter = new SemanticSymbol;
                    parameter.name = p.name.value.dup;
                    parameter.type = p.type;
                    parameter.kind = CompletionKind.variableName;
                    parameter.startLocation = p.name.startIndex;
                    symbol.children ~= parameter;
//					Log.trace("Parameter ", parameter.name, " added to ", symbol.name);
                }
            }
            else
                parameterString = "()";

            static if (is (DeclarationType == FunctionDeclaration))
                symbol.callTip = "%s %s%s".format(formatNode(dec.returnType),
					dec.name.value, parameterString);
            else
                symbol.callTip = "this%s".format(parameterString);
        }

		symbol.protection = protection;
		symbol.kind = CompletionKind.functionName;
		symbol.parent = currentSymbol;
		currentSymbol = symbol;

		if (dec.functionBody !is null)
		{
			dec.functionBody.accept(this);
		}
		currentSymbol = symbol.parent;
		currentSymbol.children ~= symbol;
    }

	static string[] iotcToStringArray(const IdentifierOrTemplateChain iotc)
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

	static string formatCalltip(Type returnType, string name, Parameters parameters,
		string doc = null)
	{
		return "%s %s%s".format(formatNode(returnType), name, formatNode(parameters));
	}

	static string formatNode(T)(T node)
	{
		if (node is null) return "";
		import formatter;
		auto app = appender!(char[])();
		auto f = new Formatter!(typeof(app))(app);
		f.format(node);
		return to!string(app.data);
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
}


struct SemanticConverter
{
public:

	this(const(SemanticSymbol)* symbol, Scope* scopes)
	{
		this.sc = scopes;
		this.symbol = symbol;
	}

	void convertModule()
	{
		convertSemanticSymbol(symbol);
		assert (current !is null);
		resolveTypes(current);
	}

	void resolveTypes(const(ACSymbol*) symbol)
	{
	}

	ACSymbol* convertSemanticSymbol(const(SemanticSymbol)* symbol)
	{
		ACSymbol* s = null;
		with (CompletionKind) final switch (symbol.kind)
		{
		case moduleName:
			s = convertAggregateDeclaration(symbol);
			current = s;
			break;
		case className:
		case interfaceName:
		case structName:
		case unionName:
		case enumName:
			s = convertAggregateDeclaration(symbol);
			break;
		case enumMember:
			s = convertEnumMember(symbol);
			break;
		case variableName:
		case memberVariableName:
			s = convertVariableDeclaration(symbol);
			break;
		case functionName:
			s = convertFunctionDeclaration(symbol);
			break;
		case aliasName:
			s = convertAliasDeclaration(symbol);
			break;
		case packageName:
			assert (false, "Not implemented");
		case keyword:
		case array:
		case assocArray:
        case dummy:
			assert (false, "This should never be reached");
		}
		if (sc !is null && symbol.kind != CompletionKind.moduleName)
		{
			sc.getScopeByCursor(s.location).symbols ~= s;
//			Log.trace("Set scope location");
		}
		return s;
	}

	ACSymbol* convertAliasDeclaration(const(SemanticSymbol)* symbol)
	{
		ACSymbol* ac = new ACSymbol;
		ac.name = symbol.name;
		ac.kind = symbol.kind;
		ac.location = symbol.location;
		// TODO: Set type
		return ac;
	}

	ACSymbol* convertVariableDeclaration(const(SemanticSymbol)* symbol)
	{
		ACSymbol* ac = new ACSymbol;
		ac.name = symbol.name;
		ac.kind = CompletionKind.variableName;
		ac.location = symbol.location;
		if (symbol.type !is null)
			ac.type = resolveType(symbol.type);
		// TODO: Handle auto
		return ac;
	}

	ACSymbol* convertEnumMember(const(SemanticSymbol)* symbol)
	{
		ACSymbol* ac = new ACSymbol;
		ac.name = symbol.name;
		ac.kind = symbol.kind;
		ac.location = symbol.location;
		// TODO: type
		return ac;
	}

	ACSymbol* convertFunctionDeclaration(const(SemanticSymbol)* symbol)
	{
//		Log.trace("Converted ", symbol.name, " ", symbol.kind, " ", symbol.location);
		ACSymbol* ac = new ACSymbol;
		ac.name = symbol.name;
		ac.kind = symbol.kind;
		ac.location = symbol.location;
		ac.callTip = symbol.callTip;
		if (symbol.type !is null)
			ac.type = resolveType(symbol.type);
		return ac;
	}

    ACSymbol* convertAggregateDeclaration(const(SemanticSymbol)* symbol)
    {
//		Log.trace("Converted ", symbol.name, " ", symbol.kind, " ", symbol.location);
		ACSymbol* ac = new ACSymbol;
		ac.name = symbol.name;
		ac.kind = symbol.kind;
		ac.location = symbol.location;
		if (symbol.kind == CompletionKind.className
			|| symbol.kind == CompletionKind.structName)
		{
			ACSymbol* thisSymbol = new ACSymbol("this",
				CompletionKind.variableName, ac);
			ac.parts ~= thisSymbol;
		}
		auto temp = current;
		current = ac;
		foreach (child; symbol.children)
			current.parts ~= convertSemanticSymbol(child);
		current = temp;
        return ac;
    }

private:


	ACSymbol* resolveType(const Type t)
	in
	{
		assert (t !is null);
		assert (t.type2 !is null);
	}
	body
	{
		ACSymbol* s;
		if (t.type2.builtinType != TokenType.invalid)
			s = convertBuiltinType(t.type2);
		else if (t.type2.typeConstructor != TokenType.invalid)
			s = resolveType(t.type2.type);
		else if (t.type2.symbol !is null)
		{
			if (t.type2.symbol.dot)
				Log.error("TODO: global scoped symbol handling");
			string[] symbolParts = expandSymbol(
				t.type2.symbol.identifierOrTemplateChain);

		}
		foreach (suffix; t.typeSuffixes)
			s = processSuffix(s, suffix);
		return null;
	}

	static string[] expandSymbol(const IdentifierOrTemplateChain chain)
	{
		string[] strings = new string[chain.identifiersOrTemplateInstances.length];
		for (size_t i = 0; i != chain.identifiersOrTemplateInstances.length; ++i)
		{
			auto identOrTemplate = chain.identifiersOrTemplateInstances[i];
			strings[i] = identOrTemplate.templateInstance is null ?
				identOrTemplate.identifier.value.dup
				: identOrTemplate.identifier.value.dup;
		}
		return strings;
	}

	static ACSymbol* processSuffix(ACSymbol* symbol, const TypeSuffix suffix)
	{
		if (suffix.star)
			return symbol;
		if (suffix.array || suffix.type)
		{
			ACSymbol* s = new ACSymbol;
			s.parts = arraySymbols;
			s.type = symbol;
			s.qualifier = suffix.array ? SymbolQualifier.array : SymbolQualifier.assocArray;
			return s;
		}
		if (suffix.parameters)
		{
			Log.error("TODO: Function type suffix");
			return null;
		}
		return null;
	}

	static ACSymbol* convertBuiltinType(const Type2 type2)
	{
		string stringRepresentation = getTokenValue(type2.builtinType);
		if (stringRepresentation is null) return null;
		// TODO: Make this use binary search instead
		foreach (s; builtinSymbols)
			if (s.name == stringRepresentation)
				return s;
		return null;
	}

	ACSymbol* current;
	Scope* sc;
	const(SemanticSymbol)* symbol;
}

const(ACSymbol)*[] convertAstToSymbols(Module m)
{
    SemanticVisitor visitor = new SemanticVisitor(SemanticType.partial);
	visitor.visit(m);
    SemanticConverter converter = SemanticConverter(visitor.rootSymbol, null);
	converter.convertModule();
    return cast(typeof(return)) converter.current.parts;
}

const(Scope)* generateAutocompleteTrees(const(Token)[] tokens)
{
	Module m = parseModule(tokens, null);
	SemanticVisitor visitor = new SemanticVisitor(SemanticType.full);
	visitor.visit(m);
	SemanticConverter converter = SemanticConverter(visitor.rootSymbol,
		visitor.currentScope);
	converter.convertModule();
	return converter.sc;
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

unittest
{
	auto source = q{
		module foo;

		struct Bar { int x; int y;}
	}c;
	Module m = parseTestCode(source);
	BasicSemanticVisitor visitor = new BasicSemanticVisitor;
	visitor.visit(m);
	assert (visitor.rootSymbol !is null);
	assert (visitor.rootSymbol.name == "foo");
	SemanticSymbol* bar = visitor.root.getPartByName("Bar");
	assert (bar !is null);
	assert (bar.getPartByName("x") !is null);
	assert (bar.getPartByName("y") !is null);
}
