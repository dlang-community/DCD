module fooutils;

struct Foo {
    void fooHey(){}
}

void u(Foo foo) {}
void ufcsHello(ref Foo foo) {}
void ufcsBar(Foo foo, string mama) {}
void ufcsBarRef(ref Foo foo, string mama) {}
void ufcsBarRefConst(ref const Foo foo, string mama) {}
void ufcsBarRefConstWrapped(ref const(Foo) foo, string mama) {}
void ufcsBarRefImmuttableWrapped(ref immutable(Foo) foo, string mama) {}
void ufcsBarScope(ref scope Foo foo, string mama) {}
void ufcsBarReturnScope(return scope Foo foo, string mama) {}
private void ufcsBarPrivate(Foo foo, string message) {}