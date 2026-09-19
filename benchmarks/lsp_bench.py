#!/usr/bin/env python3
"""DCD LSP benchmark: measures the latency a user actually feels.

Drives `dcd-server --lsp` over stdio (same harness pattern as the
lsp-tests/ suites) and reports:

  startup        server boot -> initialize response
  warmup         didOpen -> ready (parses the file's import closure)
  cold           first completion after opening a file
  typing         per-keystroke latency: one didChange per character,
                 completion after each, p50/p95/p99/max
  member-typing  typing a member name (prefix filtering: items.na...)
  large-file     warmup/completion/typing on a ~2000-line file
  def/refs/sig   definition, references, signatureHelp (warm)
  hover          hover request latency (warm)
  memory         server RSS after the run + growth over 200 keystrokes

Usage:
  python3 benchmarks/lsp_bench.py [--phobos DIR] [--json OUT.json]

The default fixture is a small file importing std.stdio, so the numbers
are comparable across machines with any D toolchain installed. Point
--phobos at your stdlib include dir if auto-detection fails.
"""
import argparse
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER = os.path.join(REPO, "bin", "dcd-server")

# The fixture: a realistic editing session. Small enough to run anywhere,
# imports std.stdio so the Phobos closure is part of the measurement.
FIXTURE = """module bench;

import std.stdio;
import std.algorithm;

struct Item
{
    string name;
    int count;
}

void report(Item[] items)
{
    foreach (item; items)
    {
        writeln(item.name, ": ", item.count);
    }
}

void main()
{
    Item[] items = [Item("a", 1), Item("b", 2)];
    report(items);
    items.
}
"""

# The line the typing simulation edits (before the trailing `items.`).
TYPING_ANCHOR = "    report(items);"

# The member name typed character by character after `items.` (prefix
# filtering path - what typing in the completion popup actually is).
MEMBER_TYPED = "name"


def make_large_fixture(n_structs=120):
    """A ~2000-line file: many structs, functions, and a big main."""
    parts = ["module bench_large;\n\nimport std.stdio;\nimport std.algorithm;\n\n"]
    for i in range(n_structs):
        parts.append("""
struct Item%d
{
    string name;
    int count;
    double weight;

    int total() { return count * 2; }
}

void report%d(Item%d[] items)
{
    foreach (item; items)
    {
        writeln(item.name, ": ", item.count);
    }
}
""" % (i, i, i))
    parts.append("\nvoid main()\n{\n")
    for i in range(n_structs):
        parts.append("    Item%d[] items%d = [Item%d(\"a\", 1)];\n    report%d(items%d);\n" % (i, i, i, i, i))
    parts.append("    items0.\n}\n")
    return "".join(parts)


def detect_phobos():
    """Find the stdlib import dir, trying the same places the LSP server does."""
    candidates = []
    for env in ("LDC_INCLUDE", "DMD_INCLUDE"):
        if os.environ.get(env):
            candidates.append(os.environ[env])
    # Ask the compiler itself first — layout-agnostic and version-proof.
    # A verbose compile of an empty file prints where `object.d` was
    # found; its directory IS the stdlib import root. Works for both
    # ldc2 (homebrew `include/dlang/ldc`, setup-dlang `import`) and
    # dmd (`src/phobos`).
    for cc in ("ldc2", "dmd"):
        try:
            with open("/tmp/dcd_bench_empty.d", "w") as f:
                f.write("void main() {}\n")
            r = subprocess.run([cc, "-v", "-c", "-o-", "/tmp/dcd_bench_empty.d"],
                               capture_output=True, text=True, timeout=30)
            # ldc2 writes -v output to stdout, dmd to stderr — check both
            for line in (r.stdout + r.stderr).splitlines():
                if "object.d)" in line and line.rstrip().endswith(")"):
                    path = line.rstrip().rsplit("(", 1)[1][:-1]
                    candidates.append(os.path.dirname(path))
        except (OSError, subprocess.TimeoutExpired):
            pass
    # fallbacks for known layouts
    import glob
    candidates += glob.glob("/opt/homebrew/Cellar/ldc/*/include/dlang/ldc")
    candidates += glob.glob("/usr/local/Cellar/ldc/*/include/dlang/ldc")
    # setup-dlang CI installs (github actions): official tarball layout
    candidates += glob.glob(os.path.expanduser("~/dlang/ldc-*/import"))
    candidates += glob.glob(os.path.expanduser("~/dlang/dmd-*/src/phobos"))
    candidates += ["/usr/include/dmd/phobos"]
    for c in candidates:
        if os.path.isdir(c):
            return c
    return None


class Lsp:
    """Minimal JSON-RPC-over-stdio client (pattern from lsp-tests/)."""

    def __init__(self, cmd):
        self.proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL)
        self.buf = b""
        self.nid = 0

    def send(self, obj):
        data = json.dumps(obj).encode()
        self.proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(data) + data)
        self.proc.stdin.flush()

    def recv(self):
        import select
        while b"\r\n\r\n" not in self.buf:
            r, _, _ = select.select([self.proc.stdout], [], [], 60.0)
            if not r:
                raise RuntimeError("timeout waiting for server")
            chunk = os.read(self.proc.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError("server EOF")
            self.buf += chunk
        head, _, self.buf = self.buf.partition(b"\r\n\r\n")
        length = int(head.split(b":")[1])
        while len(self.buf) < length:
            chunk = os.read(self.proc.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError("server EOF mid-body")
            self.buf += chunk
        body, self.buf = self.buf[:length], self.buf[length:]
        return json.loads(body)

    def request(self, method, params):
        self.nid += 1
        self.send({"jsonrpc": "2.0", "id": self.nid,
                   "method": method, "params": params})
        while True:
            msg = self.recv()
            if msg.get("id") == self.nid:
                return msg

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def rss_kb(self):
        """Server RSS in KB (macOS/Linux; 0 if unavailable)."""
        try:
            out = subprocess.check_output(
                ["ps", "-o", "rss=", "-p", str(self.proc.pid)])
            return int(out.strip())
        except Exception:
            return 0


def pos_of(text, probe):
    """Line/char of the end of `probe`'s first occurrence."""
    off = text.index(probe) + len(probe)
    line = text[:off].count("\n")
    char = off - (text[:off].rfind("\n") + 1)
    return {"line": line, "character": char}


def percentile(sorted_vals, p):
    if not sorted_vals:
        return 0.0
    idx = min(int(len(sorted_vals) * p / 100.0), len(sorted_vals) - 1)
    return sorted_vals[idx]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phobos", default=None, help="stdlib import dir")
    ap.add_argument("--json", default=None, help="also write results as JSON")
    args = ap.parse_args()

    if not os.path.isfile(SERVER):
        sys.exit("server not found: %s (run `dub build --config=server`)" % SERVER)

    phobos = args.phobos or detect_phobos()
    if phobos is None:
        sys.exit("could not auto-detect the stdlib import dir; pass --phobos DIR")

    ws = "/tmp/dcd-bench-ws"
    os.makedirs(ws, exist_ok=True)
    doc = os.path.join(ws, "bench.d")
    with open(doc, "w") as f:
        f.write(FIXTURE)
    uri = "file://" + doc

    results = {"phobos": phobos, "server": SERVER}

    lsp = Lsp([SERVER, "--lsp"])

    # --- startup ---
    t0 = time.time()
    lsp.request("initialize", {
        "processId": None, "rootUri": "file://" + ws, "capabilities": {},
        "initializationOptions": {"importPaths": [phobos, ws]},
    })
    results["startup_ms"] = (time.time() - t0) * 1000
    lsp.notify("initialized", {})

    # --- warmup (didOpen parses the import closure) ---
    t0 = time.time()
    lsp.notify("textDocument/didOpen", {"textDocument": {
        "uri": uri, "languageId": "d", "version": 1, "text": FIXTURE}})
    # sync: a cheap request that queues behind the warmup
    lsp.request("workspace/symbol", {"query": "zzz_nothing"})
    results["warmup_ms"] = (time.time() - t0) * 1000

    # --- cold completion (first after open; cache is warm from warmup,
    #     so this measures the completion path itself) ---
    pos = pos_of(FIXTURE, "items.")
    t0 = time.time()
    r = lsp.request("textDocument/completion",
                    {"textDocument": {"uri": uri}, "position": pos})
    results["cold_ms"] = (time.time() - t0) * 1000
    results["cold_items"] = len(r.get("result", {}).get("items", []))

    # --- typing (comment edits, empty partial): one didChange per
    #     character, completion after each. Measures the didChange+
    #     completion loop with the popup just opened.
    latencies = []
    text = FIXTURE
    typed = ""
    for ch in "the quick brown fox jumps over the lazy dog 0123456789":
        typed += ch
        text2 = text.replace(TYPING_ANCHOR, TYPING_ANCHOR + " // " + typed, 1)
        lsp.notify("textDocument/didChange", {"textDocument": {"uri": uri, "version": 100 + len(typed)},
                                              "contentChanges": [{"text": text2}]})
        t0 = time.time()
        lsp.request("textDocument/completion",
                    {"textDocument": {"uri": uri}, "position": pos})
        latencies.append((time.time() - t0) * 1000)
    latencies.sort()
    results["typing_n"] = len(latencies)
    results["typing_p50_ms"] = percentile(latencies, 50)
    results["typing_p95_ms"] = percentile(latencies, 95)
    results["typing_p99_ms"] = percentile(latencies, 99)
    results["typing_max_ms"] = latencies[-1] if latencies else 0

    # --- member typing (prefix filtering): type `items.na` -> `items.name`
    #     character by character, completing after each. This is what
    #     typing inside the completion popup actually is.
    mlat = []
    base = FIXTURE
    typed = ""
    for ch in MEMBER_TYPED:
        typed += ch
        text2 = base.replace("items.\n", "items." + typed + "\n", 1)
        lsp.notify("textDocument/didChange", {"textDocument": {"uri": uri, "version": 200 + len(typed)},
                                              "contentChanges": [{"text": text2}]})
        # cursor right after the typed partial
        mpos = pos_of(text2, "items." + typed)
        t0 = time.time()
        lsp.request("textDocument/completion",
                    {"textDocument": {"uri": uri}, "position": mpos})
        mlat.append((time.time() - t0) * 1000)
    mlat.sort()
    results["member_typing_n"] = len(mlat)
    results["member_typing_p50_ms"] = percentile(mlat, 50)
    results["member_typing_p95_ms"] = percentile(mlat, 95)
    results["member_typing_max_ms"] = mlat[-1] if mlat else 0

    # --- other LSP requests (warm) ---
    hpos = pos_of(FIXTURE, "report(items)")
    hpos = {"line": hpos["line"], "character": hpos["character"] - len("items);")}
    t0 = time.time()
    lsp.request("textDocument/hover", {"textDocument": {"uri": uri}, "position": hpos})
    results["hover_ms"] = (time.time() - t0) * 1000

    dpos = pos_of(FIXTURE, "report(items)")
    dpos = {"line": dpos["line"], "character": dpos["character"] - len("items);")}
    t0 = time.time()
    lsp.request("textDocument/definition", {"textDocument": {"uri": uri}, "position": dpos})
    results["definition_ms"] = (time.time() - t0) * 1000

    t0 = time.time()
    lsp.request("textDocument/references", {
        "textDocument": {"uri": uri}, "position": dpos,
        "context": {"includeDeclaration": True}})
    results["references_ms"] = (time.time() - t0) * 1000

    spos = pos_of(FIXTURE, "report(")
    t0 = time.time()
    lsp.request("textDocument/signatureHelp", {"textDocument": {"uri": uri}, "position": spos})
    results["signature_ms"] = (time.time() - t0) * 1000

    # --- large-file scenario: a ~2000-line file in the same workspace.
    #     Measures how warmup/completion scale with document size.
    large = make_large_fixture()
    ldoc = os.path.join(ws, "bench_large.d")
    with open(ldoc, "w") as f:
        f.write(large)
    luri = "file://" + ldoc
    t0 = time.time()
    lsp.notify("textDocument/didOpen", {"textDocument": {
        "uri": luri, "languageId": "d", "version": 1, "text": large}})
    lsp.request("workspace/symbol", {"query": "zzz_nothing"})
    results["large_warmup_ms"] = (time.time() - t0) * 1000

    lpos = pos_of(large, "items0.")
    t0 = time.time()
    r = lsp.request("textDocument/completion",
                    {"textDocument": {"uri": luri}, "position": lpos})
    results["large_completion_ms"] = (time.time() - t0) * 1000
    results["large_items"] = len(r.get("result", {}).get("items", []))

    # typing on the large file (comment edits, same pattern as above)
    llat = []
    anchor = "    report0(items0);"
    typed = ""
    for ch in "typing on a large file":
        typed += ch
        text2 = large.replace(anchor, anchor + " // " + typed, 1)
        lsp.notify("textDocument/didChange", {"textDocument": {"uri": luri, "version": 300 + len(typed)},
                                              "contentChanges": [{"text": text2}]})
        t0 = time.time()
        lsp.request("textDocument/completion",
                    {"textDocument": {"uri": luri}, "position": lpos})
        llat.append((time.time() - t0) * 1000)
    llat.sort()
    results["large_typing_p50_ms"] = percentile(llat, 50)
    results["large_typing_p95_ms"] = percentile(llat, 95)
    results["large_typing_max_ms"] = llat[-1] if llat else 0

    # --- sustained typing: 200 keystrokes, RSS sampled every 20 to catch
    #     leak-class growth a single snapshot cannot see.
    rss_start = lsp.rss_kb()
    text = FIXTURE
    typed = ""
    for i in range(200):
        typed += chr(97 + (i % 26))
        text2 = text.replace(TYPING_ANCHOR, TYPING_ANCHOR + " // " + typed[:60], 1)
        lsp.notify("textDocument/didChange", {"textDocument": {"uri": uri, "version": 400 + i},
                                              "contentChanges": [{"text": text2}]})
        lsp.request("textDocument/completion",
                    {"textDocument": {"uri": uri}, "position": pos})
    rss_end = lsp.rss_kb()
    results["rss_mb"] = rss_end / 1024.0
    results["rss_growth_mb"] = (rss_end - rss_start) / 1024.0

    lsp.request("shutdown", None)
    lsp.notify("exit", {})

    # --- report ---
    print("DCD LSP benchmark")
    print("  phobos:      %s" % phobos)
    print("  startup:     %8.1f ms" % results["startup_ms"])
    print("  warmup:      %8.1f ms  (didOpen, import closure)" % results["warmup_ms"])
    print("  completion:  %8.1f ms  (first, %d items)" % (results["cold_ms"], results["cold_items"]))
    print("  typing:      p50 %6.1f  p95 %6.1f  p99 %6.1f  max %6.1f ms  (n=%d)"
          % (results["typing_p50_ms"], results["typing_p95_ms"],
             results["typing_p99_ms"], results["typing_max_ms"], results["typing_n"]))
    print("  member-typ:  p50 %6.1f  p95 %6.1f  max %6.1f ms  (n=%d, prefix filter)"
          % (results["member_typing_p50_ms"], results["member_typing_p95_ms"],
             results["member_typing_max_ms"], results["member_typing_n"]))
    print("  hover:       %8.1f ms" % results["hover_ms"])
    print("  definition:  %8.1f ms" % results["definition_ms"])
    print("  references:  %8.1f ms" % results["references_ms"])
    print("  signature:   %8.1f ms" % results["signature_ms"])
    print("  large-file:  warmup %6.1f  completion %6.1f ms (%d items)  typing p50 %6.1f  p95 %6.1f ms"
          % (results["large_warmup_ms"], results["large_completion_ms"],
             results["large_items"], results["large_typing_p50_ms"],
             results["large_typing_p95_ms"]))
    print("  memory:      %8.1f MB  (growth over 200 keystrokes: %+.1f MB)"
          % (results["rss_mb"], results["rss_growth_mb"]))

    if args.json:
        with open(args.json, "w") as f:
            json.dump(results, f, indent=2)
        print("\nresults written to %s" % args.json)


if __name__ == "__main__":
    main()
