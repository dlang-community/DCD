# DCD benchmarks

Latency benchmarks for the LSP server, measuring what a user actually
feels while editing. Run them before and after a performance-relevant
change and compare.

## Usage

```
dub build --config=server          # the benchmark runs bin/dcd-server
python3 benchmarks/lsp_bench.py    # prints a summary table
```

Options:

* `--phobos DIR` — stdlib import dir (auto-detected: homebrew LDC,
  ~/dlang/dmd-*, /usr/include/dmd/phobos)
* `--json OUT.json` — also write the numbers as JSON, for comparing runs

## What it measures

The fixture is a small file importing `std.stdio` and `std.algorithm`,
so the Phobos import closure is part of every run.

| Metric | Meaning |
|---|---|
| `startup` | server boot → `initialize` response |
| `warmup` | `didOpen` → ready (parses the file's import closure) |
| `completion` | first completion after open (items = result count) |
| `typing` | **per-keystroke latency**: one `didChange` per character, completion after each — p50/p95/p99/max |
| `hover` | hover request latency (warm) |
| `memory` | server RSS after the run |

## Comparing runs

```
python3 benchmarks/lsp_bench.py --json after.json
python3 - <<'EOF'
import json
before = json.load(open("/tmp/bench_baseline.json"))
after = json.load(open("after.json"))
for k in before:
    if k.endswith("_ms") or k in ("rss_mb",):
        print("%-16s %8.1f -> %8.1f" % (k, before[k], after[k]))
EOF
```

Numbers vary between runs (especially `warmup`, which is dominated by
parsing the Phobos closure); compare medians of a few runs, not single
values.

## Profiling (when a number regresses)

* **macOS**: `sample <pid> 5` snapshots call stacks of a running server —
  run the benchmark in another terminal first, then sample during the
  slow phase.
* **LDC `-profile`**: build the server with
  `dub build --config=server --build=profile` (LDC) and it writes
  `profile.log` with per-function time and hit counts.
* **Linux**: `perf record -p <pid>` / `perf report`.

## Adding scenarios

The tool is deliberately simple; extend `lsp_bench.py` with new scenarios
(edit-heavy loops, references, rename, larger fixtures) as needed. Keep
each scenario self-contained and report one line per metric so the output
stays diffable.
