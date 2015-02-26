class Alpha
{
	this(int x);
}

class Beta : Alpha
{
	this(int x, int y)
	{
		super();
		this();
	}
}

void main(string[] args)
{
	auto b = new Beta();
}
