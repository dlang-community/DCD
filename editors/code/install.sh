#!/usr/bin/env bash
# Rebuild + reinstall the DCD LSP extension end-to-end.
#
#   1. Rebuilds the D server (dub, --config=server)
#   2. Compiles the TypeScript extension
#   3. Packages a fresh .vsix (with dependencies)
#   4. Uninstalls the old extension, installs the new one
#
# Usage:
#   ./install.sh            # full rebuild + reinstall
#   ./install.sh --fast     # skip dub rebuild (reuse bin/dcd-server)
#   ./install.sh --tests    # also run the LSP test suites after install

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
NORMAL='\033[0m'

CODE_BIN="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
EXT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$EXT_DIR/../.." && pwd)"
SERVER="$REPO_ROOT/bin/dcd-server"
EXT_ID="dcd.dcd-lsp"

step() { echo -e "\n${BLUE}=== $1 ===${NORMAL}"; }
ok()    { echo -e "  ${GREEN}✓${NORMAL} $1"; }
fail()  { echo -e "  ${RED}✗ $1" >&2; exit 1; }

FAST=0
RUN_TESTS=0
for arg in "$@"; do
  case "$arg" in
    --fast)  FAST=1 ;;
    --tests) RUN_TESTS=1 ;;
    *) fail "unknown option: $arg (use --fast, --tests)" ;;
  esac
done

[[ -x "$CODE_BIN" ]] || fail "VS Code CLI not found at $CODE_BIN"

step "1/4 Rebuild D server"
if [[ "$FAST" -eq 1 ]]; then
  [[ -x "$SERVER" ]] || fail "no server at $SERVER (--fast requires an existing build)"
  ok "skipped (--fast), using existing $(basename "$SERVER")"
else
  (cd "$REPO_ROOT" && dub build --config=server --force) \
    || fail "dub build failed"
  ok "dcd-server built at $SERVER"
fi

step "2/4 Compile TypeScript extension"
(cd "$EXT_DIR" && npm run compile) || fail "tsc compile failed"
ok "extension compiled"

step "3/4 Package .vsix"
VSIX="$(cd "$EXT_DIR" && npx @vscode/vsce package --allow-missing-repository 2>/dev/null | grep -oE '/[^ ]*\.vsix' | tail -1)"
[[ -n "$VSIX" ]] || fail "vsce package failed (no .vsix produced)"
ok "packaged $(basename "$VSIX")"

step "4/4 Install into VS Code"
"$CODE_BIN" --uninstall-extension "$EXT_ID" >/dev/null 2>&1 || true
"$CODE_BIN" --install-extension "$VSIX" 2>/dev/null \
  || fail "vsix install failed"
ok "installed $EXT_ID"

if [[ "$RUN_TESTS" -eq 1 ]]; then
  step "Tests"
  (cd "$REPO_ROOT" && python3 lsp_smoke_test.py)   || fail "lsp_smoke_test.py failed"
  (cd "$REPO_ROOT" && python3 lsp_semantic_test.py) || fail "lsp_semantic_test.py failed"
  ok "LSP test suites passed"
fi

echo -e "\n${GREEN}Done. Reload VS Code (Cmd+Shift+P → Developer: Reload Window) to pick up the new build.${NORMAL}"
