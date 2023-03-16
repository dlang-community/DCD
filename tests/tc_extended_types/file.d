/// my documentation
struct S
{
	T foo(T)() { return T.init; }
}

void test()
{
	S s;
	auto bar = s.foo!int();
	bar
}
