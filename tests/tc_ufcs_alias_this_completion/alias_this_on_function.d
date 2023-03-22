struct S { S* s; S get() { return *s; } alias get this; }

void ufcsMatching(S value) {}
void ufcsNonMatching(int value) {}

void main()
{
	S s;
	s.ufcs
}