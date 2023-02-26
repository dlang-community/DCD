module dsymbol.type_lookup;

import dsymbol.string_interning;
import containers.unrolledlist;

/**
 * The type lookup kind.
 */
enum TypeLookupKind : ubyte
{
	inherit,
	aliasThis,
	initializer,
	mixinTemplate,
	varOrFunType,
	selectiveImport,
	returnType,
}

/**
 * information used by the symbol resolver to determine types, inheritance,
 * mixins, and alias this.
 */
struct TypeLookup
{
	this(TypeLookupKind kind)
	{
		this.kind = kind;
	}

	this(istring name, TypeLookupKind kind)
	{
		breadcrumbs.insert(name);
		this.kind = kind;
	}

	/// Strings used to resolve the type
	UnrolledList!istring breadcrumbs;
	/// The kind of type lookup
	TypeLookupKind kind;
}
