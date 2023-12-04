// when extending the inlayHints capabilities, don't forget to update the --help
// text inside client.d

import point;
import point : P = Point;

void foo(int x, int y) {}
void foo(Point point) {}
void bar(P point, int z = 1) {}

void main()
{
	P p;
	foo(1, 2);
	foo(p);
	bar(p, 3);
}
