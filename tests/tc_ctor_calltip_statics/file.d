module tests.tc_ctor_calltip_statics.file;

struct MyStruct
{
	int x;
	int y;
	static int counter;
	__gshared int shared_;
	enum int magic = 42;
}

struct Versioned
{
	int vx;
	version (Posix)
	{
		int posixField;
		static int posixStatic;
	}
	version (Windows) int winField;
}

void main()
{
	auto s = MyStruct(
	auto v = Versioned(
}
