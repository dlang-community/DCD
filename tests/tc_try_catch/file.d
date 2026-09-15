module tests.tc_try_catch.file;

struct Error
{
	int code;
}

void main()
{
	try
	{
		int inner;
		inner.
	}
	catch (Error e)
	{
		e.
	}
}

void unnamedCatch()
{
	try
	{
	}
	catch (Error)
	{
		int unnamed;
		unnamed.
	}
}

void localInCatchBody()
{
	try
	{
	}
	catch (Error e)
	{
		int local;
		local.
	}
}
