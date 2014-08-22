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

module stupidlog;

import std.stdio;
import core.vararg;

enum LogLevel : uint
{
	fatal = 0,
	error,
	info,
	trace
}

struct Log
{
	static void trace(T...)(T args)
	{
		if (level < LogLevel.trace) return;
		version(Windows)
		{
			output.writeln("[trace] ", args);
			return;
		}
		else
		{
			if (output is stdout)
				output.writeln("[\033[01;36mtrace\033[0m] ", args);
			else
				output.writeln("[trace] ", args);
		}
	}

	static void info(T...)(T args)
	{
		if (level < LogLevel.info) return;
		version (Windows)
		{
			output.writeln("[info ] ", args);
			return;
		}
		else
		{
			if (output is stdout)
				output.writeln("[\033[01;32minfo\033[0m ] ", args);
			else
				output.writeln("[info ] ", args);
		}
	}

	static void error(T...)(T args)
	{
		if (level < LogLevel.error) return;
		version(Windows)
		{
			output.writeln("[error] ", args);
			return;
		}
		else
		{
			if (output is stdout)
				output.writeln("[\033[01;31merror\033[0m] ", args);
			else
				output.writeln("[error] ", args);
		}
	}

	static void fatal(T...)(T args)
	{
		version(Windows)
		{
			output.writeln("[fatal] ", args);
			return;
		}
		else
		{
			if (output is stdout)
				output.writeln("[\033[01;35mfatal\033[0m] ", args);
			else
				output.writeln("[fatal] ", args);
		}
	}

	static LogLevel level;
	static File output;
}
