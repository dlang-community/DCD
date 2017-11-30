void main(string[] args)
{
	libraryFunction();
}

/// Hello
/// World
int* libraryFunction(string s) pure {
	return &libraryVariable;
}

/**
 * foobar
 */
Tuple!long libraryFunction(string s, string s2) pure @nogc {
	return tuple(cast(long) (s.length * s2.length));
}
