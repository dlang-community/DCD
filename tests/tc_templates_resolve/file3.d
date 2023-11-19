struct TopHashMap(Key, Value)
{
    Key value_key;
    Value value_value;
}

void main()
{
    auto top = TopHashMap!(int, int)();
    auto bottom = BottomHashMap!(int, int)();
    {
        top.
    }
    {
        auto copy = top;
        copy.
    }
    {
        bottom.
    }
    {
        auto copy = bottom;
        copy.
    }
    {
        auto wf = WithFunction!(int, int)();
        auto gkey = wf.get_key();
        gkey.
    }
}

struct BottomHashMap(Key, Value)
{
    Key value_key;
    Value value_value;
}

struct WithFunction(Key, Value)
{
    Key get_key()
    {
        return Key.init;
    }

    Value get_value()
    {
        return Value.init;
    }
}
