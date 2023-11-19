struct ReaderTest(bool LE)
{
    void read_test(){}
}
alias ReaderTestBE = ReaderTest!true;
struct Test
{
    void read(ReaderTestBE* reader)
    {
        reader.re
    }
}
