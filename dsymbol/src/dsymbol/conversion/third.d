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

module dsymbol.conversion.third;

import dsymbol.modulecache;
import dsymbol.scope_;
import dsymbol.semantic;
import dsymbol.symbol;
import dsymbol.string_interning;
import dsymbol.deferred;
import dsymbol.type_lookup;

import containers.hashset;
import dsymbol.coloredlogger;
import std.logger;
import std.experimental.allocator;
import std.experimental.allocator.gc_allocator;


/**
 * Used to resolve the type of remaining symbols that were left out due to modules being parsed from other modules that depend on each other (public imports)
 * It will start from the scope of interest at the cursorPosition, and it'll traverse the scope from bottom to top and check if the symbol's type is know
 * If it is, then it'll set its type
 * If the symbol is not found, then it'll do nothing 
 */
void thirdPass(SemanticSymbol* symbol, Scope* mscope, ref ModuleCache cache, size_t cursorPosition)
{
	auto desired = mscope.getScopeByCursor(cursorPosition);
	tryResolve(desired, cache);

    // now as our final step, let's try to resolve templates

    tryResolveTemplates(symbol, mscope, cache);
}

void tryResolveTemplates(SemanticSymbol* currentSymbol, Scope* mscope, ref ModuleCache cache)
{
    with (CompletionKind) switch (currentSymbol.acSymbol.kind)
    {
    case variableName:
    case memberVariableName:
        if (currentSymbol.acSymbol.type && currentSymbol.typeLookups.length > 0)
        {
            TypeLookup* lookup = currentSymbol.typeLookups.front;
            if (lookup.ctx.root)
            {
                auto type = currentSymbol.acSymbol.type;
                if (type.kind == structName || type.kind == className && lookup.ctx.root.args.length > 0)
                {
                    DSymbol*[string] mapping;
                    int depth;
                    resolveTemplate(currentSymbol.acSymbol, type, lookup, lookup.ctx.root, mscope, cache, depth, mapping);
                }
            }
        }
        else
        {
            warning("no type: ", currentSymbol.acSymbol.name," ", currentSymbol.acSymbol.kind);
        }

        break;
        default: break;
    }


    foreach (child; currentSymbol.children)
        tryResolveTemplates(child, mscope, cache);
}


DSymbol* createTypeWithTemplateArgs(DSymbol* type, TypeLookup* lookup, VariableContext.TypeInstance* ti, ref ModuleCache cache, Scope* moduleScope, ref int depth, DSymbol*[string] m)
{
    assert(type);
    warning("processing type: ", type.name, " ", ti.chain, " ", ti.args);
    DSymbol* newType = GCAllocator.instance.make!DSymbol("dummy", CompletionKind.dummy, null);
    newType.name = type.name;
    newType.kind = type.kind;
    newType.qualifier = type.qualifier;
    newType.protection = type.protection;
    newType.symbolFile = type.symbolFile;
    newType.doc = type.doc;
    newType.callTip = type.callTip;
    newType.type = type.type;
    DSymbol*[string] mapping;



    if (m)
    foreach(k,v; m)
    {
        warning("store mapping: ".yellow, k, " ", v.name);
        mapping[k] = v;
    }

    int[string] mapping_index;
    int count = 0;
    if (ti.args.length > 0)
    {
        warning("hard args, build mapping");
        foreach(part; type.opSlice())
        {
            if (part.kind == CompletionKind.typeTmpParam)
            {
                scope(exit) count++;
                
                warning("building mapping for: ", part.name, " chain: ", ti.args[count].chain);
                auto key = part.name;
                
                DSymbol* first;
                foreach(i, crumb; ti.args[count].chain)
                {
                    auto argName = crumb;
                    if (i == 0)
                    {

                        if (key in mapping)
                        {
                            //first = mapping[argName];
                            //continue;
                            argName = mapping[key].name;
                        }

                        auto result = moduleScope.getSymbolsAtGlobalScope(istring(argName));
                        if (result.length == 0)
                        {
                            error("can't find symbol: ".red, argName);

                            foreach(k, v; mapping)
                            {
                                warning("k: ", k, " v: ", v);
                            }

                            break;
                        }
                        first = result[0];
                    }
                    else {
                        first = first.getFirstPartNamed(istring(argName));
                    }
                }

                mapping_index[key] = count;
                if (first is null)
                {
                    error("can't find type for mapping: ".red, part.name);
                    continue;
                }
                warning("  map: ", key ,"->", first.name);
                
                warning("  creating type: ".blue, first.name);

                auto ca = ti.args[count];
                if (ca.chain.length > 0) 
                mapping[key] =  createTypeWithTemplateArgs(first, lookup, ca, cache, moduleScope, depth, mapping);
            }
        }
    }
    

    assert(newType);
    warning("process parts..");
    string[] T_names;
    foreach(part; type.opSlice())
    {
        if (part.kind == CompletionKind.typeTmpParam)
        {
            warning("    #", count, " ", part.name);
            T_names ~= part.name;
        }
        else if (part.type && part.type.kind == CompletionKind.typeTmpParam)
        {
            DSymbol* newPart = GCAllocator.instance.make!DSymbol(part.name, part.kind, null);
            newPart.qualifier = part.qualifier;
            newPart.protection = part.protection;
            newPart.symbolFile = part.symbolFile;
            newPart.doc = part.doc;
            newPart.callTip = part.callTip;
            newPart.ownType = false;

            if (part.type.name in mapping)
            {
                newPart.type = mapping[part.type.name];
                warning("         mapping found: ", part.type.name," -> ", newPart.type.name);
            }
            else 
            if (m && part.type.name in m)
            {
                newPart.type = m[part.type.name];
                warning("         mapping in m found: ", part.type.name," -> ", newPart.type.name);
            }
            else
                error("         mapping not found: ".red, part.type.name," type: ", type.name, " cur: ", ti.chain, "args: ", ti.args);

            newType.addChild(newPart, true);
        }
        else
        {
            //if (depth < 50)
            //if (part.type && part.kind == CompletionKind.variableName)
            //foreach(partPart; part.type.opSlice())
            //{
            //    if (partPart.kind == CompletionKind.typeTmpParam)
            //    {
            //        foreach(arg; ti.args)
            //        {
            //            warning(" >", arg.chain, " ", arg.args);
            //        }
            //        warning("go agane ".blue, part.name, " ", part.type.name, " with arg: ", ti.chain," Ts: ", T_names);
            //        //resolveTemplate(part, part.type, lookup, ti, moduleScope, cache, depth, mapping);
            //        break;
            //    }
            //}
            warning("adding untouched: ", part.name, "into: ", newType);
            newType.addChild(part, false);
        }
    }
    return newType;
}


/**
 * Resolve template arguments
 */
void resolveTemplate(DSymbol* variableSym, DSymbol* type, TypeLookup* lookup, VariableContext.TypeInstance* current, Scope* moduleScope, ref ModuleCache cache, ref int depth, DSymbol*[string] mapping = null)
{
    depth += 1;

    if (variableSym is null || type is null) return;


    warning("resolving template for var: ", variableSym.name, " type: ", type.name, "depth: ", depth);
    warning("current args: ");
    foreach(i, arg; current.args)
        warning("    i: ", i, " ", arg.chain);
    warning("current chain: ", current.chain, " name: ", current.name);
    if (current.chain.length == 0) return; // TODO: should not be empty, happens for simple stuff Inner inner;

    DSymbol* newType = createTypeWithTemplateArgs(type, lookup, current, cache, moduleScope, depth, mapping);
    



    variableSym.type = newType;
    variableSym.ownType = true;

}




/**
 * Used to resolve missing symbols within a scope
 */
void tryResolve(Scope* sc, ref ModuleCache cache)
{
    if (sc is null) return;
    auto symbols = sc.symbols;
    foreach (item; symbols)
    {
        DSymbol* target = item.type;

        if (target !is null)
        {
            HashSet!size_t visited;
            foreach (part; target.opSlice())
            {
                resolvePart(part, sc, cache, visited);
            }
        }
    }
    if (sc.parent !is null) tryResolve(sc.parent, cache);
}

void resolvePart(DSymbol* part, Scope* sc, ref ModuleCache cache, ref HashSet!size_t visited)
{
    if (visited.contains(cast(size_t) part))
        return;
    visited.insert(cast(size_t) part);

    // no type but a typeSymbolName, let's resolve its type
    if (part.type is null && part.typeSymbolName !is null)
    {
        import std.string: indexOf;
        auto typeName = part.typeSymbolName;

        // check if it is available in the scope
        // otherwise grab its module symbol to check if it's publickly available
        auto result = sc.getSymbolsAtGlobalScope(istring(typeName));
        if (result.length > 0)
        {
            part.type = result[0];
            return;
        }
        else
        {
            if (part.symbolFile == "stdin") return;
            auto moduleSymbol = cache.getModuleSymbol(part.symbolFile);
            auto first = moduleSymbol.getFirstPartNamed(istring(typeName));
            if (first !is null)
            {
                part.type = first;
                return;
            }
            else
            {
                // type couldn't be found, that's stuff like templates
                // now we could try to resolve them!
                // warning("can't resolve: ", part.name, " callTip: ", typeName);
                return;
            }
        }
    }

    if (part.type !is null)
    {
        foreach (typePart; part.type.opSlice())
            resolvePart(typePart, sc, cache, visited);
    }
}