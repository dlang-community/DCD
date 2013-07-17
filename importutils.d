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
