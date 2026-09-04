# Installing the DCD Language Server

DCD's server speaks the
[Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
directly:

```
dcd-server --lsp
```

Any LSP-capable editor — VS Code, Neovim, Emacs, Kate, Helix, and many more —
can use it. The server is a lean LSP: a thin protocol layer over DCD's
semantic engine, with no client process or socket hop in between. This guide
covers building the server, installing the VS Code extension, and wiring up
other editors.

> **Status.** The core feature set works and is covered by automated tests:
> completion, hover, go-to-definition, references, rename, signature help
> (with overload cycling), document symbols, and inlay hints, plus automatic
> import-path detection (workspace sources, dub dependencies, Phobos).
>
> Not yet implemented: incremental document sync (full sync only),
> `workspace/symbol`, formatting, `completionItem/resolve`, and
> request cancellation. Compared to the classic socket mode the semantic
> engine is shared, so engine-level limitations are identical.

## 1. Build the server

You need a recent D compiler ([dmd](https://dlang.org/download.html) or
[ldc](https://github.com/ldc-developers/ldc#installation)) and
[dub](https://dub.pm/get_started) (bundled with dmd).

From a checkout of this repository:

```sh
git submodule update --init --recursive   # first time only
dub build --config=server --build=release
```

This produces `bin/dcd-server`. Verify the LSP mode responds:

```sh
echo -e 'Content-Length: 58\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | bin/dcd-server --lsp
```

You should get a JSON response containing `"serverInfo"` with name `dcd-lsp`.

Alternatively, install a released DCD via [Homebrew](https://formulae.brew.sh/formula/dcd)
(`brew install dcd`) or your distribution's package manager — any build from
2026-08 or later includes `--lsp`.

## 2. Install the VS Code extension

The extension lives in [`editors/code/`](.). It is a thin TypeScript client
around `vscode-languageclient` — the interesting logic is all in the server,
so the extension stays small and easy to audit.

### From a checkout (recommended)

```sh
./editors/code/install.sh
```

This rebuilds the server (`dub`), compiles the extension (`tsc`), packages a
`.vsix`, and installs it into VS Code in one step. Useful flags:

* `--fast` — skip the dub rebuild, reuse the existing `bin/dcd-server`
* `--tests` — also run the LSP test suites

Reload VS Code afterwards (Cmd+Shift+P → `Developer: Reload Window`).

### From a pre-built .vsix

If you already have a `.vsix` (e.g. `dcd-lsp-0.1.0.vsix`):

```sh
code --install-extension dcd-lsp-0.1.0.vsix
```

### Extension settings

| Setting | Default | Meaning |
|---|---|---|
| `dcd.serverPath` | `"dcd-server"` | Path to the server executable. A bare name is looked up on `PATH`; a relative path is resolved against the workspace root. |
| `dcd.importPaths` | `[]` | Extra import paths, relative to the workspace root. |
| `dcd.ignoreConfig` | `false` | Skip loading `dcd.conf`. |
| `dcd.logLevel` | `"info"` | Server log verbosity; logs go to the `DCD` output channel. |
| `dcd.dscannerPath` | `"dscanner"` | Path to the [D-Scanner](https://github.com/dlang-community/D-Scanner) executable for lint diagnostics. A bare name is looked up on `PATH`; set to an empty string to disable linting. |

| `dcd.dfmtPath` | `"dfmt"` | Path to the [dfmt](https://github.com/dlang-community/dfmt) executable for code formatting (Shift+Alt+F). A bare name is looked up on `PATH`; an empty string disables formatting. |
| `dcd.dfmtBraceStyle` | `"default"` | Brace style used by dfmt when the project has no `.editorconfig`: `otbs`, `allman`, `stroustrup`, `knr`, or `default` (dfmt's built-in behavior). A project `.editorconfig` always takes precedence. |
| `dcd.autoModuleDeclaration` | `true` | Automatically add (or fix) the `module` declaration of files newly created in the editor, matching the file's path-derived module name. The edit is undoable. |

Commands: `DCD: Restart Language Server` and `DCD: Shutdown Language Server`.

### Lint diagnostics (optional, via D-Scanner)

If `dscanner` is installed, the server runs it in the background on every
file open/change and publishes the findings as diagnostics (squiggles in the
Problems panel). D-Scanner is **not** a dependency of DCD — it is executed as
an external tool, so nothing breaks when it is absent. Linting runs on a
background thread with debouncing, so it never delays completions or hovers.

Install D-Scanner with [Homebrew](https://formulae.brew.sh/formula/dscanner)
(`brew install dscanner`), from
[releases](https://github.com/dlang-community/D-Scanner/releases), or build it
from source — any executable on the `PATH` named `dscanner` is picked up
automatically.

Checks can be configured with a `dscanner.ini` file at the workspace root (see
`dscanner --defaultConfig`). When **no** `dscanner.ini` is found (neither in
the document's directory nor anywhere above it), the server passes a
generated default config that disables only the
`undocumented_declaration_check` — D-Scanner enables it out of the box, which
floods real projects with "Public declaration 'x' is undocumented" noise.
Any discovered or explicitly configured `dscanner.ini` takes precedence and
is used as-is, so projects that want the check simply enable it in their ini.
Clients can also opt out of the default via
`initializationOptions.dscanner.disableUndocumentedByDefault: false`.

### Formatting (optional, via dfmt)

If [dfmt](https://github.com/dlang-community/dfmt) is installed
(`brew install dfmt`), the server formats documents on
`textDocument/formatting` (Shift+Alt+F in VS Code). Like D-Scanner, dfmt is
executed as an external tool, not a dependency. Formatting style is configured
with an [`.editorconfig`](https://editorconfig.org) file at the project root —
the server passes the document's directory so dfmt discovers it
automatically.

When no `.editorconfig` is found, the server applies the configured brace
style via a generated config (`default` = dfmt's built-in Allman). In VS Code
this is the `dcd.dfmtBraceStyle` dropdown (`otbs`, `allman`, `stroustrup`,
`knr`, or `default`); other clients set
`initializationOptions.dfmt.braceStyle`.

### Auto module declaration

When a file is created **in the editor** (explorer "New File", a workspace
edit) and then opened within a few seconds, the server sends a
`workspace/applyEdit` request that inserts the file's module declaration —
derived from its path relative to the import paths (`source/util/helper.d` →
`module util.helper;`). A file that already declares the right module is
left alone; a wrong declaration is fixed; `package.d` files and files with a
shebang/dub.sdl preamble are handled (the declaration goes after the
preamble). The edit is a normal buffer edit: visible and undoable with one
Ctrl+Z. Files that merely appear on disk (git checkout, generators) never
trigger it — only editor-initiated creations do.

Disable it with `dcd.autoModuleDeclaration: false` (VS Code) or
`initializationOptions.autoModuleDeclaration: false` (other clients).

## 3. Other editors

The server needs no editor-specific code — point your editor's LSP client at
`dcd-server --lsp` (stdio transport).

### Neovim (native LSP)

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'd',
  callback = function(args)
    vim.lsp.start({
      name = 'dcd',
      cmd = { 'dcd-server', '--lsp' },
      root_dir = vim.fs.root(args.buf, { 'dub.json', 'dub.sdl', '.git' }),
    })
  end,
})
```

### Neovim (nvim-lspconfig)

```lua
require('lspconfig.configs').dcd = {
  default_config = {
    cmd = { 'dcd-server', '--lsp' },
    filetypes = { 'd' },
    root_dir = function(fname)
      return require('lspconfig.util').root_pattern('dub.json', 'dub.sdl', '.git')(fname)
    end,
  },
}
```

### Helix

```toml
# ~/.config/helix/languages.toml
[language-server.dcd]
command = "dcd-server"
args = ["--lsp"]

[[language]]
name = "d"
language-servers = ["dcd"]
```

### Emacs (lsp-mode / eglot)

```elisp
;; eglot
(add-to-list 'eglot-server-programs
             '((d-mode) . ("dcd-server" "--lsp")))
```

### Kate

Settings → Configure Kate → Plugins → enable *LSP Client*, then in the LSP
Client settings add a server for `D` with command `dcd-server --lsp`.

## 4. Import paths (how `import` resolution works)

The server resolves imports from several sources, in this order:

1. **Command line**: `dcd-server --lsp -I/some/path` (repeatable)
2. **`initializationOptions.importPaths`**: an array of paths sent by the
   editor client in the `initialize` request
3. **`dcd.conf`**: one directory per line, `#` comments, `${VAR}`
   expansion. Locations checked:
   * `$XDG_CONFIG_HOME/dcd/dcd.conf` (or `~/.config/dcd/dcd.conf`)
   * `/etc/dcd.conf` (fallback)
   * `dcd.conf` in the working directory (Windows)
4. **Auto-detection** (no configuration needed):
   * the workspace's own `source/`, `src/`, `import/` directories and root
   * dub dependencies from `dub.selections.json` / `dub.json` / `dub.sdl`,
     including transitive deps from `~/.dub/packages/`
   * the local Phobos installation (Homebrew LDC, system LDC, or
     `~/dlang/dmd-*`)

Auto-detection uses the workspace root the client reports in `initialize`
(`rootUri` / `rootPath` / `workspaceFolders`), so open the project folder in
your editor rather than loose files.

## 5. Troubleshooting

* **No completions for `std.*`**: the Phobos import path wasn't found. Pass
  it explicitly, e.g. `-I/opt/homebrew/Cellar/ldc/<version>/include/dlang/ldc`,
  or add it to `dcd.conf`.
* **Your own modules don't resolve**: make sure the project folder is open as
  the workspace root, or add its source directory via `-I` /
  `initializationOptions.importPaths`.
* **Server logs**: run with `--logLevel=all` (VS Code: the `DCD` output
  channel). The server exits when its stdin closes, so a dead server usually
  means the editor restarted it.
* **VS Code extension doesn't activate**: it activates on
  `workspaceContains:**/*.d` — open a folder containing `.d` files.
