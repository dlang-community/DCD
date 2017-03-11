alias T(alias X) = X;
int foo;
alias baz = T!(foo); // works
alias bar = T!foo;   // doesn't work

final class ABC
{
    static @property bool mybool()
    {
        return true;
    }
}

void main()
{
    while(!ABC.mybool) {}
}
