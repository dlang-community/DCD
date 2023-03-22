struct A { int x; }
struct B { A a; alias a this; }
struct C { B b; alias b this; }
struct D { C c; alias c this; }
struct E { D d; alias d this; }
struct F { E e; alias e this; }

void ufcsA(A a) {}
void ufcsB(B b) {}
void ufcsC(C c) {}
void ufcsD(D d) {}
void ufcsE(E e) {}

void testA()
{
	A a;
	a.ufcs // should only give ufcsA
}

void testE()
{
	E e;
	e.ufcs // should give all the ufcs methods
}