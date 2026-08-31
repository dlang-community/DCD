#!/usr/bin/env python3
"""Semantic test: completion/hover/definition on a self-contained document."""

import json
import subprocess

proc = subprocess.Popen(
    ["./bin/dcd-server", "--lsp", "--ignoreConfig", "--logLevel=critical"],
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
    ["./bin/dcd-server", "--lsp", "--ignoreConfig", "--logLevel=critical"],
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

send({"jsonrpc": "2.0", "id": 5, "method": "shutdown"})
recv()
send({"jsonrpc": "2.0", "method": "exit"})
code = proc.wait(timeout=10)
assert code == 0, f"exit code {code}"
print("SEMANTIC TESTS PASSED")
