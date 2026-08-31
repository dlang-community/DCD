#!/usr/bin/env python3
"""Smoke test for the DCD LSP server: initialize, open a doc, complete, shutdown."""

import json
import subprocess
import sys

proc = subprocess.Popen(
    ["./bin/dcd-server", "--lsp", "--ignoreConfig", "--logLevel=critical"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)


def send(msg):
    body = json.dumps(msg).encode()
    header = f"Content-Length: {len(body)}\r\n\r\n".encode()
    proc.stdin.write(header + body)
    proc.stdin.flush()


def recv():
    # read headers
    headers = {}
    while True:
        line = proc.stdout.readline()
        if line in (b"\r\n", b"\n", b""):
            break
        k, _, v = line.decode().partition(":")
        headers[k.strip().lower()] = v.strip()
    length = int(headers["content-length"])
    return json.loads(proc.stdout.read(length))


# 1. initialize
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "processId": None,
    "rootUri": None,
    "capabilities": {},
}})
resp = recv()
assert resp["id"] in (1, "1"), resp
caps = resp["result"]["capabilities"]
print("initialize OK")
print("  positionEncoding:", caps.get("positionEncoding"))
print("  completionProvider:", caps.get("completionProvider"))
print("  hoverProvider:", caps.get("hoverProvider"))
print("  definitionProvider:", caps.get("definitionProvider"))
print("  inlayHintProvider:", caps.get("inlayHintProvider"))

# 2. initialized notification
send({"jsonrpc": "2.0", "method": "initialized", "params": {}})

# 3. didOpen
source = "module test;\nimport std.stdio;\nvoid main() { writeln(\"hi\"); }\n"
send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {
    "textDocument": {
        "uri": "file:///tmp/test.d",
        "languageId": "d",
        "version": 1,
        "text": source,
    }}})

# 4. completion at "wl" -> should suggest writeln (needs std.stdio import path)
send({"jsonrpc": "2.0", "id": 2, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/test.d"},
    "position": {"line": 2, "character": 21},
}})
resp = recv()
assert resp["id"] in (2, "2"), resp
items = resp["result"]["items"]
print(f"completion OK ({len(items)} items)")
for item in items[:5]:
    print(f"  {item['label']} (kind={item.get('kind')}, detail={item.get('detail', '')!r})")

# 5. hover
send({"jsonrpc": "2.0", "id": 3, "method": "textDocument/hover", "params": {
    "textDocument": {"uri": "file:///tmp/test.d"},
    "position": {"line": 2, "character": 22},
}})
resp = recv()
assert resp["id"] in (3, "3"), resp
print("hover OK:", str(resp.get("result"))[:120])

# 6. definition
send({"jsonrpc": "2.0", "id": 4, "method": "textDocument/definition", "params": {
    "textDocument": {"uri": "file:///tmp/test.d"},
    "position": {"line": 2, "character": 22},
}})
resp = recv()
assert resp["id"] in (4, "4"), resp
print("definition OK:", str(resp.get("result"))[:120])

# 7. shutdown / exit
send({"jsonrpc": "2.0", "id": 5, "method": "shutdown"})
resp = recv()
assert resp["id"] in (5, "5") and "result" in resp, resp
print("shutdown OK")
send({"jsonrpc": "2.0", "method": "exit"})
code = proc.wait(timeout=10)
print(f"exit code: {code}")
assert code == 0, f"expected 0, got {code}"
print("ALL TESTS PASSED")
