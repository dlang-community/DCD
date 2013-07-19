module modulecache;

import std.file;
import std.datetime;

struct ModuleCache
{
    @disable this();

    bool needsReparsing(string mod)
    {
        if (!exists(mod))
            return false;
        if (mod !in modificationTimes)
            return true;
        SysTime access;
        SysTime modification;
        getTimes(mod, access, modification);
        if (modificationTimes[mod] != modification)
            return true;
        return false;
    }

    SysTime[string] modificationTimes;
}
