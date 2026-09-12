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


def recv_response():
    """Skips server-initiated notifications (e.g. window/showMessage)
    that may legally arrive between requests and responses."""
    while True:
        msg = recv()
        if "id" in msg:
            return msg
        # notification (no id): ignore


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "processId": None, "rootUri": None, "capabilities": {
        "general": {"positionEncodings": ["utf-16"]}}}})
resp = recv_response()
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
resp = recv_response()
items = resp["result"]["items"]
print(f"member completion: {len(items)} items")
for item in items:
    print(f"  {item['label']} kind={item.get('kind')} detail={item.get('detail', '')!r}")
labels = {i["label"] for i in items}
assert "x" in labels and "y" in labels and "distance" in labels, f"missing members: {labels}"

# clangd-style textEdit: every item carries the range it replaces. After
# "p." (no identifier typed) the range is empty at the cursor and the
# newText is the item's label.
te = items[0].get("textEdit")
assert te, f"no textEdit on completion item: {items[0]}"
assert te["range"]["start"] == {"line": 10, "character": 6}, te
assert te["range"]["end"] == {"line": 10, "character": 6}, te
assert te["newText"] == items[0]["label"], te
print(f"textEdit OK: empty range at cursor, newText={te['newText']!r}")

# mid-word trigger: complete inside "distance" on its USE — add a use
# first. Change the doc to have "p.distance" typed and the cursor mid-word.
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 2},
    "contentChanges": [{"text": source.replace("    p.\n", "    p.di\n")}]}})
send({"jsonrpc": "2.0", "id": 20, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 10, "character": 8},
}})
resp = recv_response()
items2 = resp["result"]["items"]
assert items2, "mid-word completion returned no items"
te2 = items2[0].get("textEdit")
assert te2, f"no textEdit: {items2[0]}"
# "    p.di" — 'di' starts at char 6 (after "    p."), cursor at char 8
assert te2["range"]["start"]["character"] == 6, te2
assert te2["range"]["end"]["character"] == 8, te2
assert te2["newText"] == items2[0]["label"], te2
print(f"mid-word textEdit OK: range 6..8, newText={te2['newText']!r}")
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 3},
    "contentChanges": [{"text": source}]}})

# definition of "p" in "p." on line 10
send({"jsonrpc": "2.0", "id": 3, "method": "textDocument/definition", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 10, "character": 5},  # on "p" in "p."
}})
resp = recv_response()
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
resp = recv_response()
result = resp["result"]
print("definition of Point (first char):", result)
assert result is not None, "definition not found on first character of symbol"
assert result["uri"] == "file:///tmp/semantic.d", result
assert result["range"]["start"]["line"] == 2, result  # struct Point decl
assert result["range"]["start"]["character"] == 7, result

# documentSymbol
send({"jsonrpc": "2.0", "id": 4, "method": "textDocument/documentSymbol", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"}}})
resp = recv_response()
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
resp = recv_response()
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
resp = recv_response()
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
resp = recv_response()
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
resp = recv_response()
assert resp["result"] is None, f"keyword should not be renameable: {resp['result']}"
print("prepareRename on keyword: null (correct)")

# rename "p" -> "point" from the declaration
send({"jsonrpc": "2.0", "id": 11, "method": "textDocument/rename", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 9, "character": 10},
    "newName": "point",
}})
resp = recv_response()
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
resp = recv_response()
assert "error" in resp, f"keyword rename should fail: {resp}"
print("rename to keyword rejected:", resp["error"]["message"])

# rename with an invalid identifier is rejected
send({"jsonrpc": "2.0", "id": 13, "method": "textDocument/rename", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 9, "character": 10},
    "newName": "1bad",
}})
resp = recv_response()
assert "error" in resp, f"invalid identifier rename should fail: {resp}"
print("rename to invalid identifier rejected:", resp["error"]["message"])


# --- module search: import completion against a real import path ---
# The server is started with --ignoreConfig, so pass an import path via
# initializationOptions like the VS Code extension does.
# --- function attributes: completion after a parameter list ---
# `void mama() |` (nothing typed) offers the post-parameter-list
# attributes (pure, nothrow, @safe, ...); `no` matches both nothrow and
# @nogc (the @-items carry filterText with the bare name).
# Compiler-verified: `ref`, `static`, `override`, `final`, `abstract`,
# `synchronized`, `__gshared` and `auto` are NOT valid in postfix
# position, and `const`/`immutable`/`inout`/`shared` are method-only.
attr_source = "void mama() \n{\n}\n"
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 230},
    "contentChanges": [{"text": attr_source}]}})
send({"jsonrpc": "2.0", "id": 231, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 0, "character": 12},
}})
resp = recv_response()
labels = {i["label"] for i in resp["result"]["items"]}
for expected in ("pure", "nothrow", "scope", "return", "@safe", "@nogc", "@property"):
    assert expected in labels, f"{expected} not offered after param list: {sorted(labels)}"
for invalid in ("ref", "static", "override", "final", "abstract", "const", "shared"):
    assert invalid not in labels, f"{invalid} offered after FREE function param list: {sorted(labels)}"
print(f"function attributes after `void mama() |`: {len(labels)} items")

# method context: const/immutable/inout/shared ARE offered
method_source = "struct S {\n    void mama() \n    {\n    }\n}\n"
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 236},
    "contentChanges": [{"text": method_source}]}})
send({"jsonrpc": "2.0", "id": 237, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 1, "character": 16},
}})
resp = recv_response()
labels = {i["label"] for i in resp["result"]["items"]}
for expected in ("const", "immutable", "inout", "shared", "pure", "nothrow"):
    assert expected in labels, f"{expected} not offered after METHOD param list: {sorted(labels)}"
print("method attributes after `void mama() |` in struct: const/immutable/inout/shared offered")

# partial `no` -> nothrow + @nogc
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 232},
    "contentChanges": [{"text": "void mama() no\n{\n}\n"}]}})
send({"jsonrpc": "2.0", "id": 233, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 0, "character": 13},
}})
resp = recv_response()
labels = {i["label"] for i in resp["result"]["items"]}
assert "nothrow" in labels and "@nogc" in labels, f"no partial: {sorted(labels)}"
nogc = [i for i in resp["result"]["items"] if i["label"] == "@nogc"][0]
assert nogc.get("filterText") == "@nogc nogc", f"filterText on @nogc: {nogc}"
print("function attributes partial `no`: nothrow + @nogc (filterText OK)")

# `@no` -> @nogc only, and the textEdit covers the `@` so committing
# does not leave a doubled `@@nogc`
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 234},
    "contentChanges": [{"text": "void mama() @no\n{\n}\n"}]}})
send({"jsonrpc": "2.0", "id": 235, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 0, "character": 14},
}})
resp = recv_response()
items = [i for i in resp["result"]["items"] if i["label"] == "@nogc"]
assert items, f"@nogc not offered for @no: {[i['label'] for i in resp['result']['items']]}"
te = items[0]["textEdit"]
assert te["range"]["start"]["character"] == 12, f"edit does not cover @no: {te}"
assert te["newText"] == "@nogc", te
print("@no partial: textEdit covers `@no` -> no double-@ on commit")

send({"jsonrpc": "2.0", "id": 5, "method": "shutdown"})
recv_response()
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
recv_response()
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
resp = recv_response()
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
resp = recv_response()
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
resp = recv_response()
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
    resp = recv_response()
    labels = {i["label"] for i in resp["result"]["items"]}
    has = "offsetof" in labels
    assert has == expect, f"offsetof after {expr!r}: got {has}, expected {expect} (items: {sorted(labels)})"
    print(f"offsetof after {expr!r}: {'offered' if has else 'not offered'} (correct)")

# --- auto-import: selective import edit on the completion item ---
# A name that is not in scope (no imports in the doc) and exists in a
# module on the import path: the completion must offer it with an
# additionalTextEdit inserting a SELECTIVE import
# (`import <module> : <symbol>;`), not a whole-module import.
autoimport_source = "void main() { sayHe }\n"
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 200},
    "contentChanges": [{"text": autoimport_source}]}})
send({"jsonrpc": "2.0", "id": 201, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 0, "character": 19},
}})
resp = recv_response()
items = resp["result"]["items"]
say = [i for i in items if i["label"] == "sayHello"]
assert say, f"sayHello not offered by auto-import: {[i['label'] for i in items]}"
# every auto-import item shows its module on every row via
# labelDetails.description (VS Code renders it grayed-out on the right)
ld = say[0].get("labelDetails", {})
assert ld.get("description") == "hello", f"no module origin on the item: {say[0]}"
edits = say[0].get("additionalTextEdits", [])
assert edits, "no additionalTextEdits on the auto-import item"
edit_text = edits[0]["newText"]
assert edit_text == "import hello : sayHello;\n", f"not a selective import: {edit_text!r}"
print(f"auto-import edit: {edit_text!r} (origin: {ld.get('description')!r})")

# after applying the edit (and committing the item), the symbol resolves
applied = edit_text + "void main() { sayHello }\n"
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 202},
    "contentChanges": [{"text": applied}]}})
send({"jsonrpc": "2.0", "id": 203, "method": "textDocument/definition", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 1, "character": 19},
}})
resp = recv_response()
result = resp["result"]
assert result is not None, "sayHello did not resolve after selective import"
assert result["uri"].endswith("hello.d") or result["uri"].endswith("package.d"), result
print(f"definition after selective import: {result['uri']}")

# --- auto-import: second symbol from the same module extends the bind list ---
# The workspace module `hello` also declares `sayBye`; with
# `import hello : sayHello;` already present, completing `sayBye` must
# APPEND to the existing bind list (TypeScript-style) instead of adding a
# second import declaration.
with open(os.path.join(ws, "source", "hello", "package.d"), "w") as f:
    f.write("module hello;\nvoid sayHello() {}\nvoid sayBye() {}\n")
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 210},
    "contentChanges": [{"text": "import hello : sayHello;\nvoid main() { sayBy }\n"}]}})
send({"jsonrpc": "2.0", "id": 211, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 1, "character": 19},
}})
resp = recv_response()
items = resp["result"]["items"]
bye = [i for i in items if i["label"] == "sayBye"]
assert bye, f"sayBye not offered: {[i['label'] for i in items]}"
edits = bye[0].get("additionalTextEdits", [])
assert edits, "no additionalTextEdits on the bind-list item"
edit = edits[0]
# `;` of "import hello : sayHello;" is at line 0, character 23
assert edit["newText"] == ", sayBye", f"not a bind-list append: {edit['newText']!r}"
assert edit["range"]["start"] == {"line": 0, "character": 23}, edit["range"]
print(f"bind-list append edit: {edit['newText']!r} at {edit['range']['start']}")

# after applying, both symbols resolve
applied2 = "import hello : sayHello, sayBye;\nvoid main() { sayBye }\n"
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 212},
    "contentChanges": [{"text": applied2}]}})
send({"jsonrpc": "2.0", "id": 213, "method": "textDocument/definition", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 1, "character": 19},
}})
resp = recv_response()
result = resp["result"]
assert result is not None, "sayBye did not resolve after bind-list append"
print(f"definition after bind-list append: {result['uri']}")

# --- auto-import: renamed binds and renamed modules still extend ---
# `import hello : sayHello, foo = sayBye;` — a renamed bind in the list
# must not confuse the append (the edit goes before the `;` regardless of
# what the list contains).
with open(os.path.join(ws, "source", "hello", "package.d"), "w") as f:
    f.write("module hello;\nvoid sayHello() {}\nvoid sayBye() {}\nvoid sayAgain() {}\n")
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 220},
    "contentChanges": [{"text": "import hello : sayHello, foo = sayBye;\nvoid main() { sayA }\n"}]}})
send({"jsonrpc": "2.0", "id": 221, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 1, "character": 18},
}})
resp = recv_response()
items = resp["result"]["items"]
again = [i for i in items if i["label"] == "sayAgain"]
assert again, f"sayAgain not offered: {[i['label'] for i in items]}"
edit = again[0]["additionalTextEdits"][0]
assert edit["newText"] == ", sayAgain", f"not an append: {edit['newText']!r}"
# `;` of "import hello : sayHello, foo = sayBye;" is at char 37
assert edit["range"]["start"] == {"line": 0, "character": 37}, edit["range"]
print(f"renamed bind append: {edit['newText']!r} at {edit['range']['start']}")

# `import h = hello : sayHello;` — a renamed MODULE: the module name is
# read from the chain after `=`, so the bind list is still extended.
send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d", "version": 224},
    "contentChanges": [{"text": "import h = hello : sayHello;\nvoid main() { sayB }\n"}]}})
send({"jsonrpc": "2.0", "id": 225, "method": "textDocument/completion", "params": {
    "textDocument": {"uri": "file:///tmp/semantic.d"},
    "position": {"line": 1, "character": 18},
}})
resp = recv_response()
items = resp["result"]["items"]
bye = [i for i in items if i["label"] == "sayBye"]
assert bye, f"sayBye not offered: {[i['label'] for i in items]}"
edit = bye[0]["additionalTextEdits"][0]
assert edit["newText"] == ", sayBye", f"not an append: {edit['newText']!r}"
# `;` of "import h = hello : sayHello;" is at char 27
assert edit["range"]["start"] == {"line": 0, "character": 27}, edit["range"]
print(f"renamed module append: {edit['newText']!r} at {edit['range']['start']}")

send({"jsonrpc": "2.0", "id": 5, "method": "shutdown"})
recv_response()
send({"jsonrpc": "2.0", "method": "exit"})
code = proc.wait(timeout=10)
assert code == 0, f"exit code {code}"
print("SEMANTIC TESTS PASSED")
