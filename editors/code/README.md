# DCD — D language support for VS Code

[DCD](https://github.com/dlang-community/DCD) (the D Completion Daemon) is a
semantic analysis tool for the [D programming language](https://dlang.org).
This extension wires VS Code to DCD's built-in
[Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
server — one process, `dcd-server --lsp`, provides all IDE features over
stdio. No socket, no separate client binary, no bundled language runtime.

## Features

* **Completion** — with documentation, resolved types, and overload bundling
  (template overloads of the same name collapse into one item)
* **Hover** — declaration signature and ddoc documentation
* **Go to definition** — including cross-file and into Phobos / dub
  dependencies
* **Find all references** — workspace-wide
* **Rename symbol** — workspace-wide, with prepare-rename validation
* **Signature help** — parameter hints with overload cycling and active
  parameter highlighting
* **Document symbols** — hierarchical outline view
* **Inlay hints** — inferred variable types and alias targets
* **Import-path auto-detection** — workspace sources, dub dependencies
  (including transitive ones from `~/.dub/packages/`), and the local Phobos
  installation are found without any configuration
* **Lint diagnostics** *(optional)* — via an external
  [D-Scanner](https://github.com/dlang-community/D-Scanner) process
* **Formatting** *(optional)* — via an external
  [dfmt](https://github.com/dlang-community/dfmt) process (Shift+Alt+F)

## Requirements

* A D compiler — [dmd](https://dlang.org/download.html) or
  [ldc](https://github.com/ldc-developers/ldc#installation) — to build the
  server (or install DCD via [Homebrew](https://formulae.brew.sh/formula/dcd)
  / your package manager)
* [dub](https://dub.pm/get_started) (bundled with dmd) to build from source

## Quick start

From a checkout of the [DCD repository](https://github.com/dlang-community/DCD):

```sh
./editors/code/install.sh
```

That builds the server, compiles and packages the extension, and installs it
into VS Code. Reload the window (Cmd+Shift+P → `Developer: Reload Window`),
then open a folder containing `.d` files.

See [INSTALL.md](./INSTALL.md) for details, other installation methods, and
setup for other editors (Neovim, Helix, Emacs, Kate).

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `dcd.serverPath` | `"dcd-server"` | Path to the server executable. A bare name is looked up on `PATH`; a relative path is resolved against the workspace root. |
| `dcd.importPaths` | `[]` | Extra import paths, relative to the workspace root. |
| `dcd.ignoreConfig` | `false` | Skip loading `dcd.conf`. |
| `dcd.logLevel` | `"info"` | Server log verbosity; logs go to the `DCD` output channel. |
| `dcd.dscannerPath` | `"dscanner"` | Path to the D-Scanner executable for lint diagnostics. A bare name is looked up on `PATH`; an empty string disables linting. |
| `dcd.dscannerConfig` | `""` | Path to a `dscanner.ini` controlling which lint checks run. Empty = dscanner discovers a `dscanner.ini` at the project root automatically. |

| `dcd.dfmtPath` | `"dfmt"` | Path to the [dfmt](https://github.com/dlang-community/dfmt) executable for code formatting (Shift+Alt+F). A bare name is looked up on `PATH`; an empty string disables formatting. |
| `dcd.dfmtBraceStyle` | `"default"` | Brace style used by dfmt when the project has no `.editorconfig`: `otbs`, `allman`, `stroustrup`, `knr`, or `default` (dfmt's built-in behavior). A project `.editorconfig` always takes precedence. |

## Commands

* `DCD: Restart Language Server`
* `DCD: Shutdown Language Server`

## Lint diagnostics (optional)

If [D-Scanner](https://github.com/dlang-community/D-Scanner) is installed
(`brew install dscanner`), the server runs it in the background on every file
open/change and publishes the findings as squiggles in the Problems panel.
D-Scanner is **not** a dependency of DCD — it is executed as an external
tool, so nothing breaks when it is absent. Linting runs on a background
thread with debouncing and never delays completions or hovers.

The `undocumented_declaration_check` is **disabled by default** — D-Scanner
enables it out of the box, which floods real projects with "Public
declaration 'x' is undocumented" noise. When no `dscanner.ini` is found in
the document's directory or above it, the server passes a generated default
config that turns just this check off. To configure checks (including
re-enabling that one), put a `dscanner.ini` at the project root — any
discovered or configured ini is used as-is:

```ini
[analysis.config.StaticAnalysisConfig]
undocumented_declaration_check="enabled"
```

Run `dscanner --defaultConfig` to see all available checks.

## Formatting (optional)

If [dfmt](https://github.com/dlang-community/dfmt) is installed
(`brew install dfmt`), `Shift+Alt+F` formats the document. Like D-Scanner,
dfmt is executed as an external tool — not a dependency of DCD. Style is
configured with an [`.editorconfig`](https://editorconfig.org) file at the
project root (indent style/size, brace style, line length, ...).

## How it works

```
VS Code ──(LSP over stdio)── dcd-server --lsp ──(external process)── dscanner
```

The extension is a thin `vscode-languageclient` wrapper; all semantic logic
lives in the server. Import resolution order: CLI `-I` flags →
`dcd.importPaths` → `dcd.conf` → auto-detection (workspace sources, dub
dependencies, Phobos).

## Status & limitations

The core feature set is stable and covered by automated tests. Not yet
implemented: incremental document sync (full sync only), `workspace/symbol`,
formatting, `completionItem/resolve`, and request cancellation. See
[INSTALL.md](./INSTALL.md#status) for details.

## License

[MIT](./LICENSE) — the extension itself; the DCD server is
[GPL-3.0](https://github.com/dlang-community/DCD/blob/master/License.txt).
