module tc_named_mixin;

template person(){}

struct nametester
{
    mixin person mainCharacter;
    mixin person sideCharacter;
}

void main()
{
    nametester n;
    n.
}
