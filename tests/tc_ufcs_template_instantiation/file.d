module tests.tc_ufcs_template_instantiation.file;

struct Box(string Tag)
{
	struct Impl { int x; }
	alias Handle = Impl*;
}

alias BoxA = Box!"a";
alias BoxB = Box!"b";

void fooA(Box!"a".Handle h) { }
void fooB(Box!"b".Handle h) { }

void fooAliasA(BoxA.Handle h) { }
void fooAliasB(BoxB.Handle h) { }

void fooBareA(BoxA a) { }
void fooBareB(BoxB b) { }

void main()
{
	Box!"a".Handle h;
	h.
}
