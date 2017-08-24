abstract class InheritMe(T)
{
	final abstract class GrandChild(U, V)
	{
		/// I am uvalue
		static U uvalue;

		/// I am vvalue
		static V vvalue;

		/// I am setGrandChild
		static void setGrandChild(alias X, alias Y)()
		{
			X = Y;
		}
	}
}


final abstract class Parent(T)
{
	/// I am stringChild
	final abstract class StringChild : InheritMe!(string)
	{
		/// I am a string GrandChild
		alias s = GrandChild!(T, string);

		/// I am an int GrandChild
		alias i = GrandChild!(T, int);
	}

	/// I am a parentF
	static void parentF()
	{

	}
}

/// I am stringParent
alias stringParent = Parent!string;

void main(string[] args)
{
	with(stringParent.StringChild.s)
	{
		setGrandChild
		!(
			uvalue, "test",
		)();
	}
}
