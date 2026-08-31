import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;

/**
 * Detects the Phobos import directory of an installed D compiler.
 * Checks DMD (dmd, ~/dlang/dmd-*) and LDC (ldc2, homebrew) install locations.
 */
function detectPhobosPath(): string | undefined {
  const candidates: string[] = [];

  // Homebrew LDC
  const brewPrefix = '/opt/homebrew/Cellar/ldc';
  if (fs.existsSync(brewPrefix)) {
    try {
      const versions = fs.readdirSync(brewPrefix).sort().reverse();
      for (const v of versions) {
        candidates.push(path.join(brewPrefix, v, 'include', 'dlang', 'ldc'));
      }
    } catch { /* ignore */ }
  }

  // LDC via PATH (ldc2 --version would be needed; use common install dirs)
  candidates.push('/usr/local/include/dlang/ldc');
  candidates.push('/usr/include/dlang/ldc');

  // DMD via install script (~/dlang/dmd-<version>/...)
  const dlangDir = path.join(os.homedir(), 'dlang');
  if (fs.existsSync(dlangDir)) {
    try {
      const entries = fs.readdirSync(dlangDir).filter(e => e.startsWith('dmd-')).sort().reverse();
      for (const e of entries) {
        candidates.push(path.join(dlangDir, e, 'src', 'phobos'));
        candidates.push(path.join(dlangDir, e, 'src', 'druntime', 'import'));
      }
    } catch { /* ignore */ }
  }

  for (const c of candidates) {
    try {
      if (fs.existsSync(path.join(c, 'std'))) {
        return c;
      }
    } catch { /* ignore */ }
  }
  return undefined;
}

export function activate(_context: vscode.ExtensionContext) {
  const config = vscode.workspace.getConfiguration('dcd');
  const outputChannel = vscode.window.createOutputChannel('DCD');
  const log = (msg: string) => {
    const line = `[${new Date().toLocaleTimeString()}] ${msg}`;
    outputChannel.appendLine(line);
    console.log(`[dcd-lsp] ${msg}`);
  };

  // Log the currently open file whenever the active editor changes
  vscode.window.onDidChangeActiveTextEditor(editor => {
    if (editor) {
      log(`ACTIVE FILE: ${editor.document.uri.toString()} (language=${editor.document.languageId})`);
    } else {
      log('ACTIVE FILE: (no editor)');
    }
  });
  // Log whatever is open right at activation
  if (vscode.window.activeTextEditor) {
    log(`ACTIVE FILE: ${vscode.window.activeTextEditor.document.uri.toString()} (language=${vscode.window.activeTextEditor.document.languageId})`);
  }

  log('=== Extension activating ===');

  const serverPathSetting = config.get<string>('serverPath', 'dcd-server');
  const serverPath = path.isAbsolute(serverPathSetting)
    ? serverPathSetting
    : path.join(vscode.workspace.workspaceFolders?.[0].uri.fsPath ?? '', serverPathSetting);

  log(`serverPath setting: ${serverPathSetting}`);
  log(`resolved serverPath: ${serverPath}`);
  log(`serverPath exists: ${fs.existsSync(serverPath)}`);

  const args: string[] = ['--lsp'];
  if (config.get<boolean>('ignoreConfig', false)) {
    args.push('--ignoreConfig');
  }
  const logLevel = config.get<string>('logLevel', 'info');
  if (logLevel && logLevel !== 'info') {
    args.push(`--logLevel=${logLevel}`);
    log(`server logLevel: ${logLevel}`);
  }

  const importPaths = config.get<string[]>('importPaths', []);
  const workspaceRoot = vscode.workspace.workspaceFolders?.[0].uri.fsPath;
  log(`workspaceRoot: ${workspaceRoot ?? '(none)'}`);
  log(`importPaths setting: ${JSON.stringify(importPaths)}`);
  const resolvedImportPaths = (importPaths ?? []).map(p =>
    path.isAbsolute(p) ? p : path.join(workspaceRoot ?? '', p)
  );

  // Auto-detect Phobos so `import std.*` resolves out of the box
  const phobos = detectPhobosPath();
  if (phobos) {
    resolvedImportPaths.push(phobos);
    log(`auto-detected Phobos: ${phobos}`);
  } else {
    log('WARNING: no Phobos found — std.* imports will NOT resolve!');
  }

  log(`final importPaths sent to server: ${JSON.stringify(resolvedImportPaths)}`);
  log(`server command: ${serverPath} ${args.join(' ')}`);

  const serverOptions: ServerOptions = {
    command: serverPath,
    args,
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: 'file', language: 'd' }],
    outputChannel,
    initializationOptions: {
      importPaths: resolvedImportPaths,
    },
    middleware: {
      // Log every document event VS Code sends us
      didOpen: (doc: vscode.TextDocument, next: (d: vscode.TextDocument) => Promise<void>) => {
        log(`didOpen: ${doc.uri.toString()} (language=${doc.languageId})`);
        return next(doc);
      },
      didChange: (event: vscode.TextDocumentChangeEvent,
        next: (e: vscode.TextDocumentChangeEvent) => Promise<void>) => {
        for (const change of event.contentChanges) {
          const text = change.text.replace(/\n/g, '\\n');
          log(`INPUT: "${text}" at line ${change.range.start.line}, char ${change.range.start.character} (len ${change.text.length})`);
        }
        return next(event);
      },
      didClose: (doc: vscode.TextDocument, next: (d: vscode.TextDocument) => Promise<void>) => {
        log(`didClose: ${doc.uri.toString()}`);
        return next(doc);
      },
      // Log every completion request VS Code sends us, and what the server returned
      provideCompletionItem: (doc: vscode.TextDocument, position: vscode.Position,
        context: vscode.CompletionContext, token: vscode.CancellationToken,
        next: (d: vscode.TextDocument, p: vscode.Position, c: vscode.CompletionContext,
          t: vscode.CancellationToken) =>
          vscode.ProviderResult<vscode.CompletionList | vscode.CompletionItem[]>) => {
        log(`completion REQUESTED: ${doc.uri.toString()} at line ${position.line}, char ${position.character} (trigger=${context.triggerKind})`);
        const result = next(doc, position, context, token);
        // Handle both sync (CompletionList) and async (Thenable) results
        if (result && typeof (result as PromiseLike<unknown>).then === 'function') {
          return (result as PromiseLike<
            vscode.CompletionList | vscode.CompletionItem[]
          >).then(items => {
            const count = Array.isArray(items) ? items.length : items?.items?.length ?? 0;
            log(`completion RESULT: ${count} item(s)`);
            return items;
          }, err => {
            log(`completion FAILED: ${err}`);
            return [] as vscode.CompletionItem[];
          });
        }
        const items = result as vscode.CompletionList | vscode.CompletionItem[] | undefined;
        const count = Array.isArray(items) ? items.length : items?.items?.length ?? 0;
        log(`completion RESULT: ${count} item(s)`);
        return result;
      },
    },
  };

  client = new LanguageClient(
    'dcd-lsp',
    'D (DCD)',
    serverOptions,
    clientOptions
  );

  client.start().then(
    () => log('client.start() resolved — server is running'),
    (err) => log(`client.start() FAILED: ${err}`)
  );
  log('client.start() called (async)');
}

export function deactivate(): Thenable<void> | undefined {
  if (!client) {
    return undefined;
  }
  return client.stop();
}
