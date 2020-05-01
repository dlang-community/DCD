import std.algorithm;
import std.ascii;
import std.conv;
import std.exception;
import std.file;
import std.path;
import std.process;
import std.range;
import std.string;

void main()
{
    auto dir = environment.get("DUB_PACKAGE_DIR");
    auto hashFile = dir.buildPath("..", "bin", "dubhash.txt");
    auto gitVer = executeShell("git -C " ~ dir ~ " describe --tags");
    auto ver = (gitVer.status == 0 ? gitVer.output.strip
            : "v" ~ dir.dirName.baseName.findSplitAfter(
                environment.get("DUB_ROOT_PACKAGE") ~ "-")[1]).ifThrown("0.0.0")
        .chain(newline).to!string.strip;
    dir.buildPath("..", "bin").mkdirRecurse;
    if (!hashFile.exists || ver != hashFile.readText.strip)
        hashFile.write(ver);
}
