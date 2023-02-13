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


struct MyTemplate(T)
{
    T T_value;
    Other!(T) other;

    T get_this_value(T)()
    {
        return T_value;
    }
}
struct Fat
{
    struct Outter
    {
        struct Inner(T)
        {
            T from_inner_T;
        }
        int from_outter;
    }
    struct Other
    {
        int from_other;
    }
    struct Agane
    {
        int from_agane;
    }
    int from_fat;
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

    // import std;
    from_auto.agane_one.yo.agane_inner.y;
    
    //writeln(typeid(from_auto.agane_one.yo.agane_inner));
    //writeln(typeid(from_auto.agane_one.yo.agane_T));
    //writeln(typeid(from_auto.agane_one.yo.what));
}









/** 
                                Inner(IdentifierOrTemplateInstance) 
        
            [One,                               Two]
    [Fat,           Outter]             [A,             B]




 */