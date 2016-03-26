/** documentation for g */
int g; /// more documentation for g

/// test
alias cool = string; /// which comment is there?

/// doc1
int a, /// doc2
	b, /** doc3 */ /**doc3.5*/
	c; /// doc4

/**
 * stuff
 */
int d; /** what could go wrong? */

/** abc */
/** def */
int e;

unittest
{
	a;
	b;
	c;
	d;
	e;
	g;
	cool;
}

/** This is not a newline: \n But this is: */
/** This is not a newline either: $(D '\n') */
int f;

unittest
{
	f;
}
