module tests.tc_ufcs_ref_base_param.file;

class Hello {
    int age;
}

class Mello : Hello {

}

void test(ref Hello hello) {

}

void hel() {
    Mello m = new Mello();
    m.
}
