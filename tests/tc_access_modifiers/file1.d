import tc_access_modifiers.bar;

struct X
{
	public int mypublic;
	private int myprivate;
}

void main()
{
	Helper helper;
	helper.mfield;
	helper.mfunc;
	X foo;
	foo.myp;
}
