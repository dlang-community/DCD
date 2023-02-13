struct Data
{
    float inside_data;
    Inner inner;
}

struct Inner
{
    float inside_inner;
}

struct AganeOne(T)
{
    T yo;
}

struct AganeTwo(T, U)
{
    T yo_T;
    U yo_U;
}

struct Other(T)
{
    T what;
    AganeOne!(T) agane_T;
    AganeOne!(Inner) agane_inner;
}

struct One(T){ T inside_one; }

struct Outter {
    struct Two(T, U){ T agane_one; U agane_two;  One!(T) one_agane_one; }
}

struct A{ int inside_a;}
struct B{ int inside_b;}


void main()
{
    auto from_auto = Outter.Two!(
                                    AganeOne!(Other!Data),
                                    AganeTwo!(A, B)
                                );
    from_auto.agane_two.yo
}
