module tests.tc_ufcs_alias_pointer_type.file;

struct Wrapper
{
	struct Impl { int x; }
	alias Handle = Impl*;
}

void foo()
{
	Wrapper.Handle h;
	h.
}

void bar(Wrapper.Handle s)
{
}
