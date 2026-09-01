#!/usr/bin/env python3
"""End-to-end test of workspace-wide rename over LSP.

Workspace layout:
  source/app.d      — declares `greet` (function) and uses it
  source/helper.d   — uses `greet` (imports app)
  source/other.d    — declares an UNRELATED `greet` (must NOT be renamed)

Rename `greet` -> `salute` from app.d; expect edits in app.d and helper.d
but NOT in other.d.
"""
import json, os, shutil, subprocess, sys, threading

REPO = "/Users/danvu/code/dlang/DCD"
SERVER = os.path.join(REPO, "bin", "dcd-server")
WS = "/tmp/dcd-wide-rename"

APP = """module app;

import helper;

void greet(string name)
{
}

void run()
{
    greet("world");
    helper.cheer("hi");
}
"""

HELPER = """module helper;

public import other;
import app;

void cheer(string msg)
{
    greet(msg);
}
"""

OTHER = """module other;

void greet(int n)
{
}
"""

def setup():
    shutil.rmtree(WS, ignore_errors=True)
    os.makedirs(os.path.join(WS, "source"))
    for name, text in [("app.d", APP), ("helper.d", HELPER), ("other.d", OTHER)]:
        with open(os.path.join(WS, "source", name), "w") as f:
            f.write(text)

class Lsp:
    def __init__(self):
        self.proc = subprocess.Popen([SERVER, "--lsp"], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.buf = b""

    def send(self, obj):
        data = json.dumps(obj).encode()
        self.proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(data) + data)
        self.proc.stdin.flush()

    def recv(self):
        while b"\r\n\r\n" not in self.buf:
            chunk = self.proc.stdout.read(1)
            if not chunk:
                raise RuntimeError("server EOF: " + self.proc.stderr.read().decode())
            self.buf += chunk
        head, _, self.buf = self.buf.partition(b"\r\n\r\n")
        length = int(head.split(b":")[1])
        while len(self.buf) < length:
            self.buf += self.proc.stdout.read(length - len(self.buf))
        body, self.buf = self.buf[:length], self.buf[length:]
        return json.loads(body)

    def request(self, obj):
        self.send(obj)
        while True:
            msg = self.recv()
            if msg.get("id") == obj.get("id"):
                return msg

    def notify(self, obj):
        self.send(obj)

def uri(path):
    return "file://" + path

def main():
    setup()
    lsp = Lsp()
    lsp.request({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                 "params": {"processId": None, "rootUri": uri(WS), "capabilities": {}}})
    lsp.notify({"jsonrpc": "2.0", "method": "initialized", "params": {}})

    app_path = os.path.join(WS, "source", "app.d")
    with open(app_path) as f:
        app_text = f.read()
    lsp.notify({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {
        "textDocument": {"uri": uri(app_path), "languageId": "d",
                         "version": 1, "text": app_text}}})

    # cursor on the declaration `greet` in app.d
    decl_off = app_text.index("greet")
    line = app_text[:decl_off].count("\n")
    char = decl_off - (app_text[:decl_off].rfind("\n") + 1)

    prep = lsp.request({"jsonrpc": "2.0", "id": 2, "method": "textDocument/prepareRename",
                        "params": {"textDocument": {"uri": uri(app_path)},
                                   "position": {"line": line, "character": char}}})
    print("prepareRename:", json.dumps(prep.get("result")))
    assert prep.get("result"), "prepareRename returned null"
    assert prep["result"]["placeholder"] == "greet"

    ren = lsp.request({"jsonrpc": "2.0", "id": 3, "method": "textDocument/rename",
                       "params": {"textDocument": {"uri": uri(app_path)},
                                  "position": {"line": line, "character": char},
                                  "newName": "salute"}})
    result = ren.get("result")
    if ren.get("error"):
        print("ERROR:", ren["error"])
        return 1

    changes = result.get("documentChanges", [])
    summary = {}
    for ch in changes:
        u = ch["textDocument"]["uri"]
        summary[u] = [(e["range"]["start"]["line"], e["range"]["start"]["character"],
                       e["newText"]) for e in ch["edits"]]
    for u, edits in sorted(summary.items()):
        print(" ", u.replace(WS, "."), "->", edits)

    ok = True
    app_edits = summary.get(uri(app_path), [])
    helper_edits = summary.get(uri(os.path.join(WS, "source", "helper.d")), [])
    other_edits = summary.get(uri(os.path.join(WS, "source", "other.d")), [])

    # app.d: declaration + call site = 2 edits
    if len(app_edits) != 2:
        print("FAIL: expected 2 edits in app.d, got", len(app_edits)); ok = False
    # helper.d: the use inside cheer = 1 edit
    if len(helper_edits) != 1:
        print("FAIL: expected 1 edit in helper.d, got", len(helper_edits)); ok = False
    # other.d: unrelated greet(int) must NOT be touched
    if other_edits:
        print("FAIL: other.d should have 0 edits, got", other_edits); ok = False

    print("RESULT:", "PASS" if ok else "FAIL")
    lsp.request({"jsonrpc": "2.0", "id": 99, "method": "shutdown", "params": None})
    lsp.notify({"jsonrpc": "2.0", "method": "exit"})
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
