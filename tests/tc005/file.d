import std.stdio;

final abstract class ABC
{
	static @property bool mybool()
	{
		return true;
	}
}

void main(string[] s)
{
	while(!ABC.mybool) {}
}
// Regression test for issue 182
