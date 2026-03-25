struct Foo {}
Foo foo(Foo f){
	return f;
}

Foo bar(Foo f){
	return f;
}

Foo baz(Foo f) {
	return f;
}


void main()
{
	Foo f;
	Foo foo = baz(f.foo().bar()).
}