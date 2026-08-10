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

Foo qux(Foo f) {
	return f;
}

ref refFoo(ref Foo f) {
	return f;
}

ref refFoo2(ref Foo f) {
	return f;
}

void main()
{
	Foo f;
	Foo foo = baz(f.foo().bar()).
}

void another() {
	Foo f;
	Foo foo = f.foo().bar().baz().
}

void yetAnother() {
	Foo f;
	Foo foo = f.foo.bar().baz.qux.
}

void justAnother() {
	Foo f;
	Foo foo = f.foo().baz().qux()
	.
}

void refTest() {
	Foo f;
	f.
}

Mama mamaFoo(Mama m) {
	return m;
}

Mama mamaBar(Mama m, int y) {
	return m;
}

Papa mamaToPapa(Mama m) {
	return Papa.init;
}

Papa papaOnly(Papa p) {
	return p;
}

struct Mama {
}
struct Papa {}

void moreTesting() {
	Mama m;
	auto ms = m.mamaFoo.mamaToPapa.
}