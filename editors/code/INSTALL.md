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

Commands: `DCD: Restart Language Server` and `DCD: Shutdown Language Server`.

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
