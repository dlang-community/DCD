module fooutils;

struct Foo {
    void fooHey(){}
}

void u(Foo foo) {}
Foo ufcsSelf(ref Foo foo) { return foo; }
int ufcsGetNumber(ref Foo foo, int number) { return number; }
void ufcsHello(ref Foo foo) {}
void ufcsBar(Foo foo, string mama) {}
void ufcsBarRef(ref Foo foo, string mama) {}
void ufcsBarRefConst(ref const Foo foo, string mama) {}
void ufcsBarRefConstWrapped(ref const(Foo) foo, string mama) {}
void ufcsBarRefImmuttableWrapped(ref immutable(Foo) foo, string mama) {}
void ufcsBarScope(ref scope Foo foo, string mama) {}
void ufcsBarReturnScope(return scope Foo foo, string mama) {}
private void ufcsBarPrivate(Foo foo, string message) {}
void helloNumber(int message) {}
bool isEvenNumber(int number) { return number % 2 == 0; }
float getBoolToFloat(bool result) { return result ? 1.0 : 0.0; }
int multiply1000(float x) { return x * 1000; }
