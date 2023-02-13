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


void main()
{
    auto from_auto = Outter.Two!(
                                    AganeOne!(Other!(Data)),
                                    AganeTwo!(A, B)
                                )();


    auto check = from_auto;
    
    
    
    import std;

    // should be of type Inner, completion: inside_inner








    writeln(typeid(from_auto.agane_one)); //file1.AganeOne!(file1.Other!(file1.Data).Other).AganeOne
    writeln(typeid(from_auto.agane_one.yo)); // file1.Other!(file1.Data).Other 
    writeln(typeid(from_auto.agane_one.yo.agane_inner)); // file1.AganeOne!(file1.Inner).AganeOne
    writeln(typeid(from_auto.agane_one.yo.agane_inner.yo)); // file1.Inner
}


// struct S { int x; int y; }

// S doStuff(int x) { return S(); }

// void main(string[] args)
// {
// 	auto alpha = 10;
// 	auto bravo = S(1, 2);
// 	int charlie = 4;
// 	auto delta = doStuff();
// 	{
// 		alpha
// 	}
// 	{
// 		bravo.
// 	}
// 	{
// 		charlie.
// 	}
// 	{
// 		delta.
// 	}
// }

