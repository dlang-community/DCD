interface Base {void foo();} class Derived : Base {int i; void foo(){}} void main(){Derived d; d.Base.f}
