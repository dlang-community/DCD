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
    One!A from_normal_one;
    Two!(A, B) from_normal_two;
    {
        from_normal_one.
    }
    {
        from_normal_two.
    }
}
