#!/usr/bin/env python3
"""Semantic test: completion/hover/definition on a self-contained document."""

import json
import os
import subprocess

# Repo root is the parent of this script's directory (lsp-tests/).
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER = os.path.join(REPO, "bin", "dcd-server")

proc = subprocess.Popen(
    [SERVER, "--lsp", "--ignoreConfig", "--logLevel=critical"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
)


def send(msg):
    body = json.dumps(msg).encode()
    proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
    proc.stdin.flush()


def recv():
    headers = {}
    while True:
        line = proc.stdout.readline()
        if line in (b"\r\n", b"\n", b""):
            break
        k, _, v = line.decode().partition(":")
        headers[k.strip().lower()] = v.strip()
    length = int(headers["content-length"])
    return json.loads(proc.stdout.read(length))


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "processId": None, "rootUri": None, "capabilities": {
        "general": {"positionEncodings": ["utf-16"]}}}})
resp = recv()
# server should fall back to utf-16 when client doesn't offer utf-8
assert resp["result"]["capabilities"]["positionEncoding"] == "utf-16", resp["result"]["capabilities"]
send({"jsonrpc": "2.0", "method": "initialized", "params": {}})

source = (
    "module test;\n"
    "\n"
    "struct Point {\n"
    "    int x;\n"
    "    int y;\n"
    "    double distance() { return 0.0; }\n"
    "}\n"
    "\n"
    "void main() {\n"
    "    Point p;\n"
    "    p.\n"
    "}\n"
)
send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {
    "textDocument": {
        "uri": "file:///tmp/semantic.d",
        "languageId": "d",
        "version": 1,
        "text": source,
    }}})

# completion after "p." on line 10 (0-based), character 6
send({"jsonrpc": "2.0", "id": 2, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 10, "character": 6},
}})
resp = recv()
items = resp["result"]["items"]
print(f"member completion: {len(items)} items")
for item in items:
    print(f"  {item['label']} kind={item.get('kind')} detail={item.get('detail', '')!r}")
labels = {i["label"] for i in items}
assert "x" in labels and "y" in labels and "distance" in labels, f"missing members: {labels}"

# definition of "p" in "p." on line 10
send({"jsonrpc": "2.0", "id": 3, "method": "textDocument/definition", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 10, "character": 5},  # on "p" in "p."
}})
resp = recv()
result = resp["result"]
print("definition of p:", result)
assert result is not None, "definition not found"
assert result["uri"] == "file:///tmp/semantic.d", result
# "Point p;" is on line 9 (0-based), "p" at character 10
assert result["range"]["start"]["line"] == 9, result
assert result["range"]["start"]["character"] == 10, result

# definition with cursor on the FIRST character of the symbol:
# "    Point p;" — "P" of Point at line 9, character 4. DCD's cursor
# semantics count bytes *before* the cursor, so a cursor exactly on the
# token's first byte used to exclude it from the token chain.
send({"jsonrpc": "2.0", "id": 6, "method": "textDocument/definition", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 9, "character": 4},  # on "P" (first char of Point)
}})
resp = recv()
result = resp["result"]
print("definition of Point (first char):", result)
assert result is not None, "definition not found on first character of symbol"
assert result["uri"] == "file:///tmp/semantic.d", result
assert result["range"]["start"]["line"] == 2, result  # struct Point decl
assert result["range"]["start"]["character"] == 7, result

# documentSymbol
send({"jsonrpc": "2.0", "id": 4, "method": "textDocument/documentSymbol", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"}}})
resp = recv()
symbols = resp["result"]
print(f"documentSymbol: {len(symbols)} symbols")
for s in symbols:
    print(f"  {s['name']} kind={s['kind']}")
names = {s["name"] for s in symbols}
assert "Point" in names and "main" in names, f"missing symbols: {names}"

# --- references: all uses of "p" within the document ---
# "p" is declared at line 9 char 10 ("Point p;") and used at line 10
# char 4 ("p.").
send({"jsonrpc": "2.0", "id": 7, "method": "textDocument/references", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 10, "character": 4},  # on "p" in "p."
    "context": {"includeDeclaration": True},
}})
resp = recv()
locs = resp["result"]
print(f"references of p: {len(locs)} refs")
for l in locs:
    s = l["range"]["start"]
    print(f"  {l['uri']}:{s['line']}:{s['character']}")
assert locs is not None, "references not found"
assert len(locs) == 2, f"expected decl + 1 use, got {len(locs)}"
assert all(l["uri"] == "file:///tmp/semantic.d" for l in locs), locs
ref_lines = sorted(l["range"]["start"]["line"] for l in locs)
assert ref_lines == [9, 10], f"unexpected reference lines: {ref_lines}"

# references with includeDeclaration: false — only the use remains
send({"jsonrpc": "2.0", "id": 8, "method": "textDocument/references", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 10, "character": 4},
    "context": {"includeDeclaration": False},
}})
resp = recv()
locs = resp["result"]
print(f"references of p (no decl): {len(locs)} refs")
assert len(locs) == 1, f"expected 1 use without declaration, got {len(locs)}"
assert locs[0]["range"]["start"]["line"] == 10, locs

# --- rename: prepareRename + rename on the local variable "p" ---
# "p" is declared at line 9 char 10 ("Point p;") and used at line 10
# char 4 ("p.").
send({"jsonrpc": "2.0", "id": 9, "method": "textDocument/prepareRename", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 9, "character": 10},
}})
resp = recv()
result = resp["result"]
print("prepareRename on decl:", result)
assert result is not None, "prepareRename returned null on declaration"
assert result["placeholder"] == "p", result
assert result["range"]["start"]["line"] == 9, result
assert result["range"]["start"]["character"] == 10, result
assert result["range"]["end"]["character"] == 11, result

# prepareRename on a keyword ("struct", line 2) is not renameable
send({"jsonrpc": "2.0", "id": 10, "method": "textDocument/prepareRename", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 2, "character": 2},
}})
resp = recv()
assert resp["result"] is None, f"keyword should not be renameable: {resp['result']}"
print("prepareRename on keyword: null (correct)")

# rename "p" -> "point" from the declaration
send({"jsonrpc": "2.0", "id": 11, "method": "textDocument/rename", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 9, "character": 10},
    "newName": "point",
}})
resp = recv()
result = resp["result"]
print(f"rename p -> point: {len(result['documentChanges'][0]['edits'])} edits")
assert result is not None, "rename returned null"
changes = result["documentChanges"]
assert len(changes) == 1, changes
assert changes[0]["textDocument"]["uri"] == "file:///tmp/semantic.d", changes
# OptionalVersionedTextDocumentIdentifier requires version to be null or an
# integer — without it vscode-languageserver-protocol rejects the edit with
# "Unknown workspace edit change received"
assert changes[0]["textDocument"]["version"] is None, changes
edits = changes[0]["edits"]
assert len(edits) == 2, f"expected decl + 1 use, got {len(edits)}"
assert all(e["newText"] == "point" for e in edits), edits
edit_lines = sorted(e["range"]["start"]["line"] for e in edits)
assert edit_lines == [9, 10], f"unexpected rename edit lines: {edit_lines}"

# rename with a keyword as the new name is rejected
send({"jsonrpc": "2.0", "id": 12, "method": "textDocument/rename", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 9, "character": 10},
    "newName": "struct",
}})
resp = recv()
assert "error" in resp, f"keyword rename should fail: {resp}"
print("rename to keyword rejected:", resp["error"]["message"])

# rename with an invalid identifier is rejected
send({"jsonrpc": "2.0", "id": 13, "method": "textDocument/rename", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 9, "character": 10},
    "newName": "1bad",
}})
resp = recv()
assert "error" in resp, f"invalid identifier rename should fail: {resp}"
print("rename to invalid identifier rejected:", resp["error"]["message"])


# --- module search: import completion against a real import path ---
# The server is started with --ignoreConfig, so pass an import path via
# initializationOptions like the VS Code extension does.
send({"jsonrpc": "2.0", "id": 5, "method": "shutdown"})
recv()
proc.stdin.close()
proc.wait(timeout=10)

import os
import tempfile

# workspace with a module in the standard dub layout
ws = tempfile.mkdtemp(prefix="dcd-lsp-mod-")
os.makedirs(os.path.join(ws, "source", "hello"))
with open(os.path.join(ws, "source", "hello", "package.d"), "w") as f:
    f.write("module hello;\nvoid sayHello() {}\n")

proc = subprocess.Popen(
    [SERVER, "--lsp", "--ignoreConfig", "--logLevel=critical"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
)
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "processId": None, "rootUri": None, "capabilities": {
        "general": {"positionEncodings": ["utf-16"]}},
    "initializationOptions": {"importPaths": [os.path.join(ws, "source")]}}})
recv()
send({"jsonrpc": "2.0", "method": "initialized", "params": {}})

# "import he" (2 tokens) — module name completion
send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {
    "textDocument": {
        "uri": "file:///tmp/semantic.d",
        "languageId": "d",
        "version": 1,
        "text": "import he",
    }}})
send({"jsonrpc": "2.0", "id": 2, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 0, "character": 8},
}})
resp = recv()
labels = {i["label"] for i in resp["result"]["items"]}
print(f"import completion 'he': {sorted(labels)}")
assert "hello" in labels, f"module 'hello' not offered: {labels}"

# "import hello." — package contents
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 2},
    "contentChanges": [{"text": "import hello."}]}})
send({"jsonrpc": "2.0", "id": 3, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 0, "character": 13},
}})
resp = recv()
labels = {i["label"] for i in resp["result"]["items"]}
print(f"import completion 'hello.': {sorted(labels)}")
assert "package" in labels, f"'package' not offered: {labels}"

# member completion through the imported module
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 3},
    "contentChanges": [{"text": "import hello;\nvoid main() { hello. }"}]}})
send({"jsonrpc": "2.0", "id": 4, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 1, "character": 20},
}})
resp = recv()
labels = {i["label"] for i in resp["result"]["items"]}
print(f"member completion 'hello.': {sorted(labels)}")
assert "sayHello" in labels, f"sayHello not offered: {labels}"

# offsetof: offered after a field access, not after an instance or type
offsetof_source = (
    "struct S { int x; int y; static int sx; }\n"
    "void main() {\n"
    "    S s;\n"
    "    s.x.\n"
    "}\n"
)
offsetof_cases = [
    # (expression to complete after, expect offsetof)
    ("s.x.", True),    # field access
    ("s.", False),     # instance
    ("S.", False),     # type
    ("s.sx.", False),  # static field
]
offsetof_id = 100
for expr, expect in offsetof_cases:
    offsetof_id += 1
    src = (
        "struct S { int x; int y; static int sx; }\n"
        "void main() {\n"
        "    S s;\n"
        "    " + expr + "\n"
        "}\n"
    )
    send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
        "textDocument": {"uri": "file:///tmp/semantic.d", "version": offsetof_id},
        "contentChanges": [{"text": src}]}})
    line_no = 3
    char_no = 4 + len(expr)
    send({"jsonrpc": "2.0", "id": offsetof_id, "method": "textDocument/completion", "params": {
        "textDocument": {"uri": "file:///tmp/semantic.d"},
        "position": {"line": line_no, "character": char_no},
    }})
    resp = recv()
    labels = {i["label"] for i in resp["result"]["items"]}
    has = "offsetof" in labels
    assert has == expect, f"offsetof after {expr!r}: got {has}, expected {expect} (items: {sorted(labels)})"
    print(f"offsetof after {expr!r}: {'offered' if has else 'not offered'} (correct)")

send({"jsonrpc": "2.0", "id": 5, "method": "shutdown"})
recv()
send({"jsonrpc": "2.0", "method": "exit"})
code = proc.wait(timeout=10)
assert code == 0, f"exit code {code}"
print("SEMANTIC TESTS PASSED")
