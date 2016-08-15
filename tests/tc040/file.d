T[] dbGet(T)(string sql)
{
}

void main()
{
	foreach (res; dbGet!int("select * from table"))
	{
		aa[res.];
	}
}
