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

module modulecache;

import std.file;
import std.datetime;

struct ModuleCache
{
    @disable this();

    bool needsReparsing(string mod)
    {
        if (!exists(mod))
            return false;
        if (mod !in modificationTimes)
            return true;
        SysTime access;
        SysTime modification;
        getTimes(mod, access, modification);
        if (modificationTimes[mod] != modification)
            return true;
        return false;
    }

    SysTime[string] modificationTimes;
}
