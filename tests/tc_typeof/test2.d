struct MyTemplate(T)
{
	enum Enum { a, b }

	T member1;
}

MyTemplate!long global2;

void main()
{
	typeof(global2).Enum test;
	test
}

