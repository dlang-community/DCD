struct Foo {
	this(int mCtor) {}
	int member1;
}

class Bar {
	this(int mCtor) {}
	int member1;
}

unittest {
	Foo f;
	f.m
}

unittest {
	Bar b = new Bar(1);
	b.m
}