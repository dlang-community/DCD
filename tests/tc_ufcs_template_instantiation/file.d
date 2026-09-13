module tests.tc_ufcs_template_instantiation.file;

struct Box(string Tag)
{
	struct Impl { int x; }
	alias Handle = Impl*;
}

void fooA(Box!"a".Handle h) { }
void fooB(Box!"b".Handle h) { }

void main()
{
	Box!"a".Handle h;
	h.
}
