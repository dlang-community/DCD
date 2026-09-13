module tests.tc_ufcs_member_chain_shadowed.file;

struct Point { int x; int y; }
struct Ctx { Point[] arr; }

void sliceFunc(Point[] s) { }

void main()
{
	Ctx ctx;
	Point[] arr;
	ctx.arr.
}
