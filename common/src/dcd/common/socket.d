/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2015 Brian Schott
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

module dcd.common.socket;

import core.sys.posix.unistd; // getuid
import std.format;
import std.process;
import std.path;

version (OSX) version = haveUnixSockets;
version (linux) version = haveUnixSockets;
version (BSD) version = haveUnixSockets;
version (FreeBSD) version = haveUnixSockets;
version (OpenBSD) version = haveUnixSockets;
version (NetBSD) version = haveUnixSockets;
version (DragonflyBSD) version = haveUnixSockets;

enum DEFAULT_PORT_NUMBER = 9166;

string generateSocketName()
{
	version (haveUnixSockets)
	{
		immutable string socketFileName = "dcd-%d.socket".format(getuid());
		version (OSX)
			return buildPath("/", "var", "tmp", socketFileName);
		else
		{
			immutable string xdg = environment.get("XDG_RUNTIME_DIR");
			return xdg is null ? buildPath("/", "tmp", socketFileName) : buildPath(xdg,
				"dcd.socket");
		}
	}
	else
	{
		assert(0);
	}
}
