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

void main()
{
	auto from_cast = cast(A.B.C) A();
	from_ca
}
