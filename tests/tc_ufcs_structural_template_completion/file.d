module tests.tc_ufcs_structural_template_completion.file;

void takePtr(T)(T* p) { }
void takeArr(T)(T[] a) { }
void takeAny(T)(T v) { }
void takeConstrained(U : long*)(U p) { }
void takePtrPtr(int** p) { }
void takeArrPtr(int[]* p) { }

void testPointer()
{
	int* p;
	p.
}

void testArray()
{
	int[] a;
	a.
}

void testPointerToPointer()
{
	int** pp;
	pp.
}

void testPointerToArray()
{
	int[]* ap;
	ap.
}
