module tests.tc_local_use_ufcs.file;

module test;

struct Foo { int x; }

void ufcsBar(Foo foo, string message) {}

void main()
{
    auto foo = Foo();
    foo.ufcsBar("hello");
}
