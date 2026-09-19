module tests.tc_ufcs_nested_function_foreach.file;

void main() {
    int[] items;
    void foo (int item) {}
    foreach (ref item; items) {
        item.
    }
}