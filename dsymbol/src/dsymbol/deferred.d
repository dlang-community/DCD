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

module dsymbol.deferred;

import containers.unrolledlist;
import containers.openhashset;
import dsymbol.string_interning;
import dsymbol.import_;
import dsymbol.symbol;
import dsymbol.type_lookup;
import std.experimental.allocator : dispose;
import std.experimental.allocator.mallocator : Mallocator;
import dsymbol.semantic : TypeLookups, TypeLookupsAllocator;

alias ImportsAllocator = Mallocator;
alias Imports = UnrolledList!(DSymbol*, ImportsAllocator);

/**
 * Contains information for deferred type resolution
 */
struct DeferredSymbol
{
	~this()
	{
		foreach (l; typeLookups[])
			TypeLookupsAllocator.instance.dispose(l);
		foreach (i; imports[])
			ImportsAllocator.instance.dispose(i);
	}

	bool dependsOn(istring modulePath)
	{
		foreach (i; imports[])
			if (i.symbolFile == modulePath)
				return true;
		return false;
	}

	/// The symbol that needs its type resolved
	DSymbol* symbol;
	/// The imports that were in scope for the symbol's declaration'
	Imports imports;
	/// The type lookup information
	TypeLookups typeLookups;
}
