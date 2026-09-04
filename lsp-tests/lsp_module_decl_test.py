#!/usr/bin/env python3
"""End-to-end test of the auto module declaration feature.

When a file is created in the editor (workspace/didCreateFiles) and then
opened (textDocument/didOpen) within a short window, the server sends a
workspace/applyEdit request inserting the path-derived module declaration.

Cases:
  1. created + opened, empty file          -> module decl inserted at top
  2. created + opened, wrong module decl   -> module decl fixed
  3. created + opened, correct decl        -> no edit
  4. opened only (no didCreateFiles)      -> no edit (file not new)
  5. package.d                            -> no edit
  6. shebang + dub.sdl preamble           -> inserted after the preamble
  7. feature disabled via initializationOptions -> no edit
"""
import json, os, shutil, subprocess, sys

# Repo root is the parent of this script's directory (lsp-tests/).
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER = os.path.join(REPO, "bin", "dcd-server")
WS = "/tmp/dcd-module-decl"


class Lsp:
    def __init__(self, initialization_options=None):
        self.proc = subprocess.Popen(
            [SERVER, "--lsp", "--ignoreConfig", "--logLevel=critical"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.buf = b""
        self.next_id = 1
        self.server_requests = []
        self._initialize(initialization_options or {})

    def send(self, obj):
        data = json.dumps(obj).encode()
        self.proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(data) + data)
        self.proc.stdin.flush()

    def recv(self):
        while b"\r\n\r\n" not in self.buf:
            chunk = self.proc.stdout.read(1)
            if not chunk:
                raise RuntimeError("server EOF")
            self.buf += chunk
        head, _, self.buf = self.buf.partition(b"\r\n\r\n")
        length = int(head.split(b":")[1])
        while len(self.buf) < length:
            self.buf += self.proc.stdout.read(length - len(self.buf))
        body, self.buf = self.buf[:length], self.buf[length:]
        return json.loads(body)

    def request(self, method, params):
        obj = {"jsonrpc": "2.0", "id": self.next_id, "method": method,
               "params": params}
        self.next_id += 1
        self.send(obj)
        while True:
            msg = self.recv()
            if msg.get("id") == obj["id"]:
                return msg
            # server -> client request (e.g. workspace/applyEdit)
            if "method" in msg and "id" in msg:
                self.server_requests.append(msg)
                # acknowledge so the client library is happy
                self.send({"jsonrpc": "2.0", "id": msg["id"],
                           "result": {"applied": True}})

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def notify_and_sync(self, method, params):
        """Sends a notification, then a cheap request to synchronize: the
        server processes messages in order, so when the request response
        arrives, the notification (and any applyEdit it triggered) has
        been fully handled."""
        self.notify(method, params)
        # $/sync is not a real method; the server answers methodNotFound,
        # which is all we need as a barrier.
        self.request("$/sync", {})

    def _initialize(self, options):
        self.request("initialize", {
            "processId": None, "rootUri": "file://" + WS,
            "capabilities": {},
            "initializationOptions": options})
        self.notify("initialized", {})

    def drain_server_requests(self):
        """Collects server->client requests that arrived as notifications
        side traffic. applyEdit arrives as a request; respond to each."""
        # There is no reliable "flush" over a pipe; the server sends the
        # applyEdit synchronously while handling didOpen/didCreateFiles,
        # so by the time a following request returns, everything sent
        # before it has been read. This method just returns what the
        # request() loop already captured.
        return self.server_requests

    def shutdown(self):
        try:
            self.request("shutdown", None)
            self.notify("exit", None)
        except Exception:
            pass
        self.proc.wait(timeout=5)


def uri(path):
    return "file://" + path


def apply_edit_for(lsp, target_uri):
    """Returns the applyEdit request targeting target_uri, or None."""
    for msg in lsp.server_requests:
        if msg.get("method") != "workspace/applyEdit":
            continue
        edit = msg["params"]["edit"]
        for change in edit.get("documentChanges", []):
            if change["textDocument"]["uri"] == target_uri:
                return change["edits"]
    return None


def setup():
    shutil.rmtree(WS, ignore_errors=True)
    os.makedirs(os.path.join(WS, "source", "util"))


def main():
    setup()
    failures = []

    def check(name, cond, detail=""):
        print(("PASS" if cond else "FAIL"), name, detail if not cond else "")
        if not cond:
            failures.append(name)

    # --- case 1: empty new file gets a module declaration ---
    lsp = Lsp()
    f1 = os.path.join(WS, "source", "util", "helper.d")
    open(f1, "w").close()
    lsp.notify("workspace/didCreateFiles", {"files": [{"uri": uri(f1)}]})
    lsp.notify_and_sync("textDocument/didOpen", {"textDocument": {
        "uri": uri(f1), "languageId": "d", "version": 1, "text": ""}})
    edits = apply_edit_for(lsp, uri(f1))
    check("empty file -> insert", edits is not None, str(lsp.server_requests))
    if edits:
        e = edits[0]
        ok = (e["range"]["start"] == {"line": 0, "character": 0}
              and e["newText"] == "module util.helper;\n\n")
        check("empty file -> correct edit", ok, json.dumps(e))
    lsp.shutdown()

    # --- case 2: wrong module declaration gets fixed ---
    lsp = Lsp()
    f2 = os.path.join(WS, "source", "util", "display.d")
    with open(f2, "w") as f:
        f.write("module util.displaf;\n\nvoid foo() {}\n")
    lsp.notify("workspace/didCreateFiles", {"files": [{"uri": uri(f2)}]})
    lsp.notify_and_sync("textDocument/didOpen", {"textDocument": {
        "uri": uri(f2), "languageId": "d", "version": 1,
        "text": open(f2).read()}})
    edits = apply_edit_for(lsp, uri(f2))
    check("wrong decl -> fix", edits is not None)
    if edits:
        e = edits[0]
        ok = (e["range"]["start"] == {"line": 0, "character": 0}
              and e["range"]["end"] == {"line": 0, "character": 20}
              and e["newText"] == "module util.display;")
        check("wrong decl -> correct edit", ok, json.dumps(e))
    lsp.shutdown()

    # --- case 3: correct declaration -> no edit ---
    lsp = Lsp()
    f3 = os.path.join(WS, "source", "util", "good.d")
    with open(f3, "w") as f:
        f.write("module util.good;\n\nvoid foo() {}\n")
    lsp.notify("workspace/didCreateFiles", {"files": [{"uri": uri(f3)}]})
    lsp.notify_and_sync("textDocument/didOpen", {"textDocument": {
        "uri": uri(f3), "languageId": "d", "version": 1,
        "text": open(f3).read()}})
    edits = apply_edit_for(lsp, uri(f3))
    check("correct decl -> no edit", edits is None, str(edits))
    lsp.shutdown()

    # --- case 4: open without create -> no edit (not a new file) ---
    lsp = Lsp()
    f4 = os.path.join(WS, "source", "util", "existing.d")
    with open(f4, "w") as f:
        f.write("void foo() {}\n")
    lsp.notify_and_sync("textDocument/didOpen", {"textDocument": {
        "uri": uri(f4), "languageId": "d", "version": 1,
        "text": open(f4).read()}})
    edits = apply_edit_for(lsp, uri(f4))
    check("open only -> no edit", edits is None, str(edits))
    lsp.shutdown()

    # --- case 5: package.d -> no edit ---
    lsp = Lsp()
    os.makedirs(os.path.join(WS, "source", "pkg"), exist_ok=True)
    f5 = os.path.join(WS, "source", "pkg", "package.d")
    open(f5, "w").close()
    lsp.notify("workspace/didCreateFiles", {"files": [{"uri": uri(f5)}]})
    lsp.notify_and_sync("textDocument/didOpen", {"textDocument": {
        "uri": uri(f5), "languageId": "d", "version": 1, "text": ""}})
    edits = apply_edit_for(lsp, uri(f5))
    check("package.d -> no edit", edits is None, str(edits))
    lsp.shutdown()

    # --- case 6: shebang + dub.sdl preamble -> insert after it ---
    lsp = Lsp()
    f6 = os.path.join(WS, "source", "script.d")
    preamble = "#!/usr/bin/env dub\n/+ dub.sdl:\n\tname \"hello\"\n+/\n"
    with open(f6, "w") as f:
        f.write(preamble + "void main() {}\n")
    lsp.notify("workspace/didCreateFiles", {"files": [{"uri": uri(f6)}]})
    lsp.notify_and_sync("textDocument/didOpen", {"textDocument": {
        "uri": uri(f6), "languageId": "d", "version": 1,
        "text": open(f6).read()}})
    edits = apply_edit_for(lsp, uri(f6))
    check("shebang -> insert", edits is not None)
    if edits:
        e = edits[0]
        # insertion point: after the 4-line preamble (shebang line +
        # 3-line dub.sdl comment block) = line 4, character 0
        ok = (e["range"]["start"] == {"line": 4, "character": 0}
              and e["newText"] == "module script;\n\n")
        check("shebang -> correct position", ok, json.dumps(e))
    lsp.shutdown()

    # --- case 7: disabled via initializationOptions ---
    lsp = Lsp({"autoModuleDeclaration": False})
    f7 = os.path.join(WS, "source", "util", "disabled.d")
    open(f7, "w").close()
    lsp.notify("workspace/didCreateFiles", {"files": [{"uri": uri(f7)}]})
    lsp.notify_and_sync("textDocument/didOpen", {"textDocument": {
        "uri": uri(f7), "languageId": "d", "version": 1, "text": ""}})
    edits = apply_edit_for(lsp, uri(f7))
    check("disabled -> no edit", edits is None, str(edits))
    lsp.shutdown()

    print("RESULT:", "PASS" if not failures else "FAIL (%s)" % failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
