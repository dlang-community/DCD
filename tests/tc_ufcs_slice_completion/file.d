module tests.tc_ufcs_slice_completion.file;

struct Point { int x; int y; }

void sliceFunc(Point[] s) { }
void elemFunc(Point e) { }

void main()
{
	Point[] arr;
	arr[1..2].
}
