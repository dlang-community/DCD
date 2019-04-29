module tc_access_modifiers.bar;

class Helper
{
	private int mfieldPrivate;
	protected int mfieldProtected;
	package int mfieldPackage;
	int mfieldPublic;

	private void mfuncPrivate() {}
	public void mfuncPublic() {}
	private static void mfuncPrivateStatic() {}
	public static void mfuncPublicStatic() {}
}
