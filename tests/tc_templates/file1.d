struct Data
{
    int inside_data;
    Inner inner;
}

struct Inner
{
    int inside_inner;
}

struct AganeOne(T)
{
    int inside_aganeone;
    T yo;
}

struct AganeTwo(T, U)
{
    int inside_aganetwo;
    T yo_T;
    U yo_U;
}

struct Other(T)
{
    int inside_other;
    T what;
    AganeOne!(T) agane_T;
    AganeOne!(Inner) agane_inner;
}

struct One(T){ T inside_one; }

struct Outter {
    struct Two(T, U){ int inside_two; T agane_one; U agane_two;  One!(T) one_agane_one; }
}

struct A{ int inside_a;}
struct B{ int inside_b;}


void main()
{
    auto from_auto = Outter.Two!(
                                    AganeOne!(Other!(Data)),
                                    AganeTwo!(A, B)
                                );
    

    import std;
    writeln(typeid(from_auto.agane_one.yo.agane_inner.yo));
}


