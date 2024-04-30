// This generates functions with all specified test types as first argument +
// variables for each specified test type.
// Then it calls all functions with every type to see which ones are accepted by
// the compiler, to automatically stay up-to-date.

import std;
import fs = std.file;

string[] testTypes = [
	"bool",
	"byte",
	"ubyte",
	"short",
	"ushort",
	"int",
	"uint",
	"long",
	"ulong",
	"char",
	"wchar",
	"dchar",
	"float",
	"double",
	"real",
	"BasicStruct",
	"AliasThisInt",
];
// index here must map onto varTypePermutations index
string[][] funcTypePermutations = [
	// TODO: check for const/inout/immutable/shared in UFCS checks
	[
		"%s",
		// "const(%s)",
		"ref %s",
		// "ref const(%s)"
	],
	[
		"%s*",
		// "const(%s)*",
		// "const(%s*)",
		"ref %s*",
		// "ref const(%s)*",
		// "ref const(%s*)"
	],
	[
		"%s[]",
		// "const(%s)[]",
		// "const(%s[])",
		"ref %s[]",
		// "ref const(%s)[]",
		// "ref const(%s[])"
	]
];
string[][] varTypePermutations = [
	[
		"%s",
		// "const(%s)"
	],
	[
		"%s*",
		// "const(%s)*",
		// "const(%s*)"
	],
	[
		"%s[]",
		// "const(%s)[]",
		// "const(%s[])"
	]
];

string preamble = `
struct BasicStruct { int member1; string member2; }
struct AliasThisInt { int member1; string member2; alias member1 this; }

`;

int main(string[] args)
{
	string functionsCode;
	string varsCode;
	string callCode;

	string[] allFunctions;
	string[string] funcLookup;
	string[string] varLookup;

	foreach (ti, type; testTypes)
	{
		foreach (pi, perms; funcTypePermutations)
		{
			foreach (i, perm; perms)
			{
				string resolved = format(perm, type);
				string id = getID(ti, pi, i);
				allFunctions ~= ("func_" ~ id);
				functionsCode ~= "void func_" ~ id ~ "(" ~ resolved ~ " arg) {}\n";
				functionsCode ~= resolved ~ " make_" ~ id ~ "() { static " ~ resolved
					.chompPrefix("ref ") ~ " x; return x; }\n";
				funcLookup["func_" ~ id] = resolved;
			}
		}
		foreach (pi, perms; varTypePermutations)
		{
			foreach (i, perm; perms)
			{
				string resolved = format(perm, type);
				string id = getID(ti, pi, i);
				varsCode ~= resolved ~ " var_" ~ id ~ " = make_" ~ id ~ "();\n";
				varLookup["var_" ~ id] = resolved;
				foreach (cti, subType; testTypes)
					foreach (ci, subPerms; funcTypePermutations)
						foreach (fi, subPerm; subPerms)
						{
							callCode ~= "var_" ~ id ~ ".func_" ~ getID(cti, ci, fi) ~ "();\n";
						}
			}
		}
	}

	allFunctions.sort!"a<b";

	string code = preamble
		~ functionsCode
		~ "\nvoid main() {\n"
		~ varsCode
		~ callCode
		~ "}\n";
	string[] lines = code.splitLines;

	fs.write("proc_test.d", code);

	// $DC and $ERROR_FLAGS are set up in run.sh
	auto output = executeShell("$DC $ERROR_FLAGS -c proc_test.d").output;

	size_t numErrors = 0;

	string[][string] variableIncompatibilities;

	// Example of a line we want to match: `proc_test.d:2568:22: error: [...]'
	auto errRegex = regex(`proc_test\.d:([0-9]*):[0-9]*: error`, "i");
	foreach (err; output.lineSplitter)
	{
		if (auto m = matchFirst(err, errRegex)) {
			auto lineNo = to!int(m[1]);
			string line = lines[lineNo - 1];
			enforce(line.endsWith("();"), "Unexpected error in line " ~ lineNo.to!string);
			line = line[0 .. $ - 3];
			string varName = line.findSplit(".")[0];
			string funcName = line.findSplit(".")[2];
			// writeln("variable type ", varLookup[varName], " can't call ", funcLookup[funcName]);
			variableIncompatibilities[varName] ~= funcName;
			numErrors++;
		}
	}

	enforce(numErrors > 1_000, "compiler didn't error as expected, need to adjust tests!");

	writeln("Total incompatible type combinations: ", numErrors);

	string[][string] wrongDCDCompletions;

	foreach (varName; varLookup.byKey)
	{
		string input = code[0 .. $ - 2]
			~ "\n"
			~ varName ~ ".func_";

		string[] dcdClient = ["../../../bin/dcd-client"];
		if (args[1].length)
			dcdClient ~= args[1];

		auto proc = pipeProcess(dcdClient ~ ["-c" ~ to!string(input.length)]);
		proc.stdin.rawWrite(input);
		proc.stdin.rawWrite("\n}\n");
		proc.stdin.close();

		string[] dcdResult;

		size_t i = 0;
		foreach (line; proc.stdout.byLineCopy)
		{
			if (i++ == 0)
			{
				enforce(line == "identifiers");
				continue;
			}

			auto parts = line.split("\t");
			if (parts[1] != "F")
				continue;
			dcdResult ~= parts[0];
		}

		enforce(i > 0, "every variable must auto-complete something! Missing completion for var " ~ varName
				~ " of type " ~ varLookup[varName] ~ generateEmptyResponseReproductionCode(
					varLookup[varName]));
		enforce(dcdResult.length > 0, "Wrongly no UFCS completion for var " ~ varName
				~ " of type " ~ varLookup[varName] ~ generateEmptyResponseReproductionCode(
					varLookup[varName]));

		dcdResult.sort!"a<b";

		string[] minusExpect = variableIncompatibilities[varName];
		minusExpect.sort!"a<b";
		variableIncompatibilities[varName] = minusExpect = minusExpect.uniq.array;

		auto neededFunctions = setDifference(allFunctions, minusExpect);

		auto unneccessaryFunctions = setDifference(dcdResult, neededFunctions);
		auto missingFunctions = setDifference(neededFunctions, setIntersection(
				dcdResult, neededFunctions));

		string[] diff =
			unneccessaryFunctions.map!(ln => '+' ~ ln)
				.chain(missingFunctions.map!(ln => '-' ~ ln))
				.array;

		// writeln(varLookup[varName], " -> ", dcdResult);
		if (diff.length)
			wrongDCDCompletions[varName] = diff;
	}

	foreach (varName, wrongTypes; wrongDCDCompletions)
	{
		writeln("Incorrect results for ", varLookup[varName], ":");
		wrongTypes.sort!"a<b";
		char prevChar = ' ';
		foreach (wrongType; wrongTypes)
		{
			if (prevChar != wrongType[0])
			{
				prevChar = wrongType[0];
				if (prevChar == '+')
					writeln("\tDCD errornously matched these argument types:");
				else if (prevChar == '-')
					writeln("\tDCD errornously did not match these argument types:");
			}

			wrongType = wrongType[1 .. $];
			writeln("\t\t", funcLookup[wrongType]);
		}
		writeln();
	}

	return wrongDCDCompletions.length ? 1 : 0;
}

string getID(size_t ti, size_t pi, size_t i)
{
	return format!"%s_%s_%s"(ti, pi, i);
}

string generateEmptyResponseReproductionCode(string type)
{
	string prefix =
		"void ufcsFunc(" ~ type ~ " v) {}\n\n"
		~ "void main() {\n"
		~ "    " ~ type ~ " myVar;\n"
		~ "    myVar.ufcs";
	return "\n\nReproduction code:\n```d\n"
		~ prefix ~ ";\n"
		~ "}\n"
		~ "```\n\n"
		~ "call `dcd-client -c" ~ prefix.length.to!string ~ "`";
}
