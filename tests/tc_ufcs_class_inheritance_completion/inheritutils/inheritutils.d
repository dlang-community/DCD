module inheritutils;

class B { }
class C : B { }
interface I { }
class D : B, I { }
class E : C { }

void ufcsBase(B b) {}
void ufcsDerived(C c) {}
void ufcsInterface(I i) {}
void ufcsBaseArray(B[] b) {}
void ufcsRefBase(ref B b) {}
