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
    struct Two(T, U){ int inside_two; T agane_one; U agane_two;  One!(T) one_agane_one; T get_T(T)(){return T.init;} U get_U(){return U.init;} }
}

struct A{ int inside_a;}
struct B{ int inside_b;}
struct C{ int inside_c;}

struct What
{
    int inside_what;
    const(V) get_it(T, U, V)() { return T.init; }
}

void main()
{
    auto from_auto = Outter.Two!(
        AganeOne!(Other!(Data)),
        AganeTwo!(A, B)
    )();

    Outter.Two!(
        AganeOne!(Other!(Data)),
        AganeTwo!(A, Other!(B))
    ) from_normal;

    auto u = from_auto.get_U();
    auto uuu = from_normal.agane_two;
    
    auto v = from_normal.get_U();

    What what;
    auto it = what.get_it!(A, B, C)();

    {
        from_auto.agane_one.
    }
    {
        from_auto.agane_two.
    }
    {
        from_normal.agane_two.
    }
    {
        from_normal.agane_two.
    }
    {
        u.
    }
    {
        uuu.
    }
    {
        uuu.
    }
    {
        it.
    }
    
}