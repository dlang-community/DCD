struct HashMap(Key, Value)
{
    Key value_key;
    Value value_value;
}

void main()
{
    auto hmap = HashMap!(int, int)();
    hmap.
}