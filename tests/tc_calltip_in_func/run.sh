set -e
set -u

../../bin/dcd-client $1 -c66 <<< "class Bar{void fun(A param){}}class Foo{void foo(Bar bar){bar.fun(}}" > actual.txt
diff actual.txt expected.txt
