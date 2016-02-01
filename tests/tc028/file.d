struct Bob
{
    version (all)
    {
    }
    else
    {
        @disable this();
    }

    int abcde;
}

unittest
{
	ab
}
