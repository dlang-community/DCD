struct A
{
    int inside_a;
}
struct B
{
    int inside_b;
}
struct One(T)
{
    T value_t;
    One!T one_t;
}

struct Two(T, U)
{
    T value_t;
    U value_u;
}

void main()
{
    auto from_auto_one = One!A();
    auto from_auto_two = Two!(A, B)();
    {
        from_auto_one.
    }
    {
        from_auto_two.
    }
}
