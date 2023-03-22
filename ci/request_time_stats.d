import core.time;
import std.algorithm;
import std.conv;
import std.format;
import std.stdio;
import std.string;

void main()
{
	long[] shortRequests, longRequests;

	foreach (line; stdin.byLine)
	{
		auto index = line.countUntil("Request processed in ");
		if (index == -1)
		{
			stderr.writeln("Warning: skipping unknown line for stats: ", line);
			continue;
		}
		index += "Request processed in ".length;
		auto dur = line[index .. $].parseDuration;
		if (dur != Duration.init)
		{
			if (dur >= 10.msecs)
				longRequests ~= dur.total!"hnsecs";
			else
				shortRequests ~= dur.total!"hnsecs";
		}
	}

	if (shortRequests.length > 0)
	{
		writeln("STAT:short requests: (", shortRequests.length, "x)");
		summarize(shortRequests);
	}
	writeln("STAT:");
	if (longRequests.length > 0)
	{
		writeln("STAT:long requests over 10ms: (", longRequests.length, "x)");
		summarize(longRequests);
	}
}

void summarize(long[] hnsecs)
{
	hnsecs.sort!"a<b";

	auto minRequest = hnsecs[0];
	auto maxRequest = hnsecs[$ - 1];
	auto medianRequest = hnsecs[$ / 2];
	auto p10Request = hnsecs[$ * 10 / 100];
	auto p90Request = hnsecs[$ * 90 / 100];

	writeln("STAT:    min request time = ", minRequest.formatHnsecs);
	writeln("STAT:    10th percentile  = ", p10Request.formatHnsecs);
	writeln("STAT:    median time      = ", medianRequest.formatHnsecs);
	writeln("STAT:    90th percentile  = ", p90Request.formatHnsecs);
	writeln("STAT:    max request time = ", maxRequest.formatHnsecs);
}

string formatHnsecs(T)(T hnsecs)
{
	return format!"%9.3fms"(cast(double)hnsecs / cast(double)1.msecs.total!"hnsecs");
}

Duration parseDuration(scope const(char)[] dur)
{
	auto origDur = dur;
	scope (failure)
		stderr.writeln("Failed to parse ", origDur);
	Duration ret;
	while (dur.length)
	{
		dur = dur.stripLeft;
		if (dur.startsWith(","))
			dur = dur[1 .. $].stripLeft;
		if (dur.startsWith("and"))
			dur = dur[3 .. $].stripLeft;
		auto num = dur.parse!int;
		dur = dur.stripLeft;
		switch (dur.startsWith(num == 1 ? "minute" : "minutes", num == 1 ? "sec" : "secs", "ms", "μs", num == 1 ? "hnsec" : "hnsecs"))
		{
		case 1:
			dur = dur[(num == 1 ? "minute" : "minutes").length .. $];
			ret += num.minutes;
			break;
		case 2:
			dur = dur[(num == 1 ? "sec" : "secs").length .. $];
			ret += num.seconds;
			break;
		case 3:
			dur = dur["ms".length .. $];
			ret += num.msecs;
			break;
		case 4:
			dur = dur["μs".length .. $];
			ret += num.usecs;
			break;
		case 5:
			dur = dur[(num == 1 ? "hnsec" : "hnsecs").length .. $];
			ret += num.hnsecs;
			break;
		default:
			stderr.writeln("Warning: unimplemented duration parsing for ", origDur, " (at ", dur, ")");
			return Duration.init;
		}
	}
	return ret;
}
