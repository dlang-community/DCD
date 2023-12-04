struct A
{
	struct B
	{
		struct C
		{
			int inside_c;
		}
		int inside_b;
	}
	int inside_a;
}

unittest
{
	auto from_cast = cast(A.B.C) nonExist;
	from_cast.
}

unittest
{
	struct A {}

	auto from_cast = cast(A.B.C) nonExist;
	from_cast.
}
