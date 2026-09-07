module tests.tc_string_mixin.file2;

enum Gen( string name ) = "struct " ~ name ~ "_T; alias " ~ name ~ " = " ~ name ~ "_T*;";
mixin( Gen!q{MyType} );
void main()
{
    MyType x;
}
