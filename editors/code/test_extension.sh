#!/usr/bin/env bash
# DCD LSP Extension Test Suite
# Tests the full chain: build → package → install → server → completion
# Usage: ./test_extension.sh [--skip-install]

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NORMAL='\033[0m'

PASS=0
FAIL=0
SKIP=0

CODE_BIN="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
EXT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$EXT_DIR/../.." && pwd)"
SERVER="$REPO_ROOT/bin/dcd-server"
INSTALLED_EXT="$HOME/.vscode/extensions/dcd.dcd-lsp-0.1.0"
PHOBOS="/opt/homebrew/Cellar/ldc/1.41.0_1/include/dlang/ldc"

section() { echo -e "\n${BLUE}=== $1 ===${NORMAL}"; }
ok()      { echo -e "  ${GREEN}✓ PASS${NORMAL} $1"; PASS=$((PASS+1)); }
bad()     { echo -e "  ${RED}✗ FAIL${NORMAL} $1"; FAIL=$((FAIL+1)); }
warn()    { echo -e "  ${YELLOW}! WARN${NORMAL} $1"; SKIP=$((SKIP+1)); }

section "1. TypeScript compiles"
if (cd "$EXT_DIR" && npm run compile >/dev/null 2>&1); then
  ok "tsc compiles cleanly"
else
  bad "tsc failed — run: cd editors/code && npm run compile"
  echo "     Cannot continue without a build."
  summary_and_exit 1
fi

section "2. Server binary exists"
if [[ -x "$SERVER" ]]; then
  ok "dcd-server at $SERVER"
else
  bad "dcd-server not found at $SERVER (run: dub build)"
  summary_and_exit 1
fi

section "3. Phobos detection"
if [[ -d "$PHOBOS/std" ]]; then
  ok "Phobos at $PHOBOS"
else
  warn "Phobos not at expected path — std.* completion may fail"
fi

section "4. LSP server: lifecycle + completion (direct protocol test)"
python3 - "$SERVER" "$PHOBOS" <<'PYEOF'
import subprocess, json, sys

server, phobos = sys.argv[1], sys.argv[2]
proc = subprocess.Popen(
    [server, "--lsp", "-I", phobos],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

def send(msg):
    body = json.dumps(msg).encode()
    proc.stdin.write(b'Content-Length: %d\r\n\r\n' % len(body) + body)
    proc.stdin.flush()

def recv():
    headers = {}
    while True:
        line = proc.stdout.readline()
        if line in (b"\r\n", b"\n", b""): break
        k, _, v = line.decode().partition(":")
        headers[k.strip().lower()] = v.strip()
    return json.loads(proc.stdout.read(int(headers["content-length"])))

results = []

def check(name, cond, detail=""):
    results.append((name, cond, detail))

try:
    # --- initialize (VS Code-style: offers both encodings) ---
    send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{
        "processId":None,"rootUri":None,
        "capabilities":{"general":{"positionEncodings":["utf-16","utf-8"]}}}})
    resp = recv()
    enc = resp["result"]["capabilities"].get("positionEncoding")
    check("initialize returns capabilities", bool(resp["result"]["capabilities"]))
    check(f"positionEncoding negotiated ({enc})", enc in ("utf-8","utf-16"))
    send({"jsonrpc":"2.0","method":"initialized","params":{}})

    # --- didOpen + member completion (in-file struct) ---
    uri = "file:///tmp/dcd_ext_test.d"
    text = ("module test;\nstruct Point { int x; int y; }\n"
            "void main() {\n    Point p;\n    p.\n}\n")
    send({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{
        "textDocument":{"uri":uri,"languageId":"d","version":1,"text":text}}})
    send({"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{
        "textDocument":{"uri":uri},"position":{"line":4,"character":6}}})
    resp = recv()
    items = resp.get("result",{}).get("items",[])
    labels = {i["label"] for i in items}
    check(f"member completion 'p.' ({len(items)} items)", "x" in labels and "y" in labels)

    # --- didChange (full sync) + identifier completion with Phobos ---
    text2 = ("import std.stdio;\nvoid main() {\n    wr\n}\n")
    send({"jsonrpc":"2.0","method":"textDocument/didChange","params":{
        "textDocument":{"uri":uri,"version":2},
        "contentChanges":[{"text": text2}]}})
    send({"jsonrpc":"2.0","id":3,"method":"textDocument/completion","params":{
        "textDocument":{"uri":uri},"position":{"line":2,"character":6},
        "context":{"triggerKind":1}}})
    resp = recv()
    items = resp.get("result",{}).get("items",[])
    labels = {i["label"] for i in items}
    check(f"identifier completion 'wr' with Phobos ({len(items)} items)",
          "writeln" in labels)

    # --- definition ---
    send({"jsonrpc":"2.0","id":4,"method":"textDocument/definition","params":{
        "textDocument":{"uri":uri},"position":{"line":2,"character":5}}})
    resp = recv()
    check("definition returns a result", "result" in resp)

    # --- documentSymbol ---
    send({"jsonrpc":"2.0","id":5,"method":"textDocument/documentSymbol","params":{
        "textDocument":{"uri":uri}}})
    resp = recv()
    syms = resp.get("result", [])
    check(f"documentSymbol ({len(syms)} symbols)", isinstance(syms, list))

    # --- shutdown/exit ---
    send({"jsonrpc":"2.0","id":6,"method":"shutdown","params":None})
    resp = recv()
    check("shutdown returns null result", resp.get("result") is None)
    send({"jsonrpc":"2.0","method":"exit"})
    proc.wait(timeout=5)
    check(f"exit code after shutdown ({proc.returncode})", proc.returncode == 0)
except Exception as e:
    check("protocol error", False, str(e))
finally:
    if proc.poll() is None:
        proc.kill()

for name, cond, detail in results:
    if cond:
        print(f"  \033[0;32m✓ PASS\033[0m {name}")
    else:
        print(f"  \033[0;31m✗ FAIL\033[0m {name} {('— '+detail) if detail else ''}")
n_pass = sum(1 for _,c,_ in results if c)
n_fail = len(results) - n_pass
with open("/tmp/dcd_test_counts", "w") as f:
    f.write(f"{n_pass} {n_fail}")
sys.exit(0 if n_fail == 0 else 1)
PYEOF
if [[ $? -eq 0 ]]; then
  read -r p f < /tmp/dcd_test_counts
  PASS=$((PASS+p)); FAIL=$((FAIL+f))
else
  read -r p f < /tmp/dcd_test_counts 2>/dev/null || { p=0; f=1; }
  PASS=$((PASS+p)); FAIL=$((FAIL+f))
fi

if [[ "${1:-}" == "--skip-install" ]]; then
  section "5. Install checks (skipped)"
  warn "skipped via --skip-install"
else
  section "5. Extension installed & current"
  if [[ -f "$INSTALLED_EXT/out/extension.js" ]]; then
    ok "extension installed at $INSTALLED_EXT"
    if diff -q "$EXT_DIR/out/extension.js" "$INSTALLED_EXT/out/extension.js" >/dev/null 2>&1; then
      ok "installed code matches current build"
    else
      bad "installed code is STALE — reinstall: vsce package && $CODE_BIN --install-extension dcd-lsp-0.1.0.vsix --force"
    fi
    if [[ -d "$INSTALLED_EXT/node_modules/vscode-languageclient" ]]; then
      ok "node_modules bundled (vscode-languageclient present)"
    else
      bad "node_modules MISSING — package WITHOUT --no-dependencies"
    fi
    if grep -q "workspaceContains" "$INSTALLED_EXT/package.json" 2>/dev/null; then
      ok "activationEvents include workspaceContains"
    else
      bad "activationEvents missing workspaceContains"
    fi
  else
    bad "extension not installed"
  fi

  section "6. VS Code window state"
  LOGDIR="$HOME/Library/Application Support/Code/logs"
  NEWEST_SESSION=$(ls -t "$LOGDIR" 2>/dev/null | head -1)
  if [[ -n "$NEWEST_SESSION" ]]; then
    ACTIVATIONS=$(grep -h "dcd.dcd-lsp" "$LOGDIR/$NEWEST_SESSION"/window*/exthost/exthost.log 2>/dev/null | grep -c "_doActivateExtension" || true)
    ERRORS=$(grep -h "dcd.dcd-lsp" "$LOGDIR/$NEWEST_SESSION"/window*/exthost/exthost.log 2>/dev/null | grep -c "failed due to an error" || true)
    if [[ "$ACTIVATIONS" -gt 0 ]]; then
      ok "extension activated in latest session ($ACTIVATIONS time(s))"
    else
      warn "no activation found in latest session — reload window & open a .d file"
    fi
    if [[ "$ERRORS" -eq 0 ]]; then
      ok "no activation errors in latest session"
    else
      bad "activation errors found — check exthost.log"
    fi
  else
    warn "no VS Code logs found"
  fi

  section "7. Running server process"
  if pgrep -f "dcd-server --lsp" >/dev/null 2>&1; then
    PID=$(pgrep -f "dcd-server --lsp" | head -1)
    CPUTIME=$(ps -p "$PID" -o time= | tr -d ' ')
    ok "dcd-server running (pid $PID, cpu $CPUTIME)"
    if [[ "$CPUTIME" == "0:00.0"* ]]; then
      warn "server has used ~no CPU — it may not have received any requests yet"
    fi
  else
    warn "no dcd-server running (window may need reload, or no .d file open)"
  fi
fi

echo -e "\n${BLUE}===============================${NORMAL}"
echo -e "${GREEN}$PASS passed${NORMAL}, ${RED}$FAIL failed${NORMAL}, ${YELLOW}$SKIP warnings${NORMAL}"
if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}SOME TESTS FAILED${NORMAL}"
  exit 1
else
  echo -e "${GREEN}ALL TESTS PASSED${NORMAL}"
  exit 0
fi
