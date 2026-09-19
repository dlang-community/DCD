module ci.lsp_bench_stats;

/**
 * Yup this is AI generated :D
 * Reads one or more lsp_bench.py JSON result files, computes the median
 * of each metric across runs, and prints one `STAT:` line per metric
 * for summary_comment_diff.sh to diff in the before/after PR comment.
 *
 * Usage: rdmd ci/lsp_bench_stats.d run1.json run2.json [run3.json ...]
 */
import std.algorithm;
import std.conv;
import std.file;
import std.json;
import std.stdio;

void main(string[] args)
{
    if (args.length < 2)
    {
        stderr.writeln("usage: ", args[0], " run1.json run2.json ...");
        return;
    }

    string[] metrics = [
        "startup_ms",
        "warmup_ms",
        "cold_ms",
        "typing_p50_ms",
        "typing_p95_ms",
        "typing_p99_ms",
        "typing_max_ms",
        "member_typing_p50_ms",
        "member_typing_p95_ms",
        "member_typing_max_ms",
        "hover_ms",
        "definition_ms",
        "references_ms",
        "signature_ms",
        "large_warmup_ms",
        "large_completion_ms",
        "large_typing_p50_ms",
        "large_typing_p95_ms",
        "large_typing_max_ms",
        "rss_mb",
        "rss_growth_mb",
    ];

    // metric -> value per run
    double[][string] runs;
    foreach (file; args[1 .. $])
    {
        if (!exists(file))
            continue;
        auto json = parseJSON(readText(file));
        foreach (m; metrics)
        {
            if (auto v = m in json.object)
                runs[m] ~= v.get!double;
        }
    }

    foreach (m; metrics)
    {
        auto vals = m in runs;
        if (vals is null || vals.length == 0)
            continue;
        auto sorted = (*vals).dup.sort!("a < b").release;
        double median = sorted.length & 1
            ? sorted[$ / 2]
            : (sorted[$ / 2 - 1] + sorted[$ / 2]) / 2;
        writefln("STAT:lsp %-24s %8.1f  (%d run%s)", m, median, sorted.length,
            sorted.length == 1 ? "" : "s");
    }
}
