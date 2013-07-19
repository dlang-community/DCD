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

module importutils;

import std.file;
import std.d.parser;
import std.d.ast;
import std.stdio;

class ImportCollector : ASTVisitor
{
    alias ASTVisitor.visit visit;

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

    string[] imports;
}

string[] getImportedFiles(Module mod, string[] importPaths)
{
    auto collector = new ImportCollector;
    collector.visit(mod);
    string[] importedFiles;
    foreach (imp; collector.imports)
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
