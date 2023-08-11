void main()
{
    foo(1);
}

/// Does foo stuff.
template foo()
{
    void foo(int a) {}
    void foo(string b) {}
}

///
unittest
{
    // usable with ints
    foo(1);
    // and with strings!
    if (auto line = readln())
        foo(line);

    // or here
    foo( 1+2 );
}

/// second usage works too
unittest
{
    foo();
}
