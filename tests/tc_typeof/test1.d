struct Result
{
	int expected;
}

struct S
{
	Result member;

	typeof(member) getMember()
	{
		return member;
	}
}

typeof(S.member) staticMember()
{
	return S.init.member;
}

void test()
{
	S s;
	auto a = S.getMember();
	auto b = staticMember();
	{
		a.
	}
	{
		b.
	}
}
