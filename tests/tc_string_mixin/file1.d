module tests.tc_string_mixin.file1;

enum VK_DEFINE_HANDLE( string name ) = "struct " ~ name ~ "_T; alias " ~ name ~ " = " ~ name ~ "_T*;";
version( D_LP64 ) {
    alias VK_DEFINE_NON_DISPATCHABLE_HANDLE( string name ) = VK_DEFINE_HANDLE!name;
} else {
    enum VK_DEFINE_NON_DISPATCHABLE_HANDLE( string name ) = "alias " ~ name ~ " = ulong;";
}
mixin( VK_DEFINE_NON_DISPATCHABLE_HANDLE!q{VkBuffer} );
mixin( VK_DEFINE_HANDLE!q{VkDevice} );
void main()
{
    VkDev
}
