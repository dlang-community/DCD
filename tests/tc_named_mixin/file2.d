module file2;

struct Foo
{
    template Deep()
    {
        int a;
    }
}

struct Bar
{
    mixin Foo.Deep d;
}

void main()
{
    Bar bar;
    bar.d.
}
