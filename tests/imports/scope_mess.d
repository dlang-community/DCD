module scope_mess;

class FooTest
{
    void member1() { int b; }
    void member2() in {} do {}
    void member3() in(true) out(a; true) do {}
    void member4() out(; things) do {}
    void member5() do {}
}
