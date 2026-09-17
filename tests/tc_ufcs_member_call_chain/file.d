module tests.tc_ufcs_member_call_chain.file;

struct Item { string name; }
struct Factory { Item make() { return Item(); } }

void useItem(Item i) { }

void main()
{
        Factory f;
        f.make().
}
