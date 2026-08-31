import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  State,
} from 'vscode-languageclient/node';

/**
 * Owns the language client lifecycle, following the clangd extension model:
 * a Disposable context pushed into `context.subscriptions`, so VS Code
 * disposes it (stopping the server) on window close, reload, and uninstall.
 */
class DcdContext implements vscode.Disposable {
  private constructor(readonly client: LanguageClient) {}

  static create(outputChannel: vscode.OutputChannel): DcdContext {
    const config = vscode.workspace.getConfiguration('dcd');
    const log = (msg: string) =>
      outputChannel.appendLine(`[${new Date().toLocaleTimeString()}] ${msg}`);

    const serverPathSetting = config.get<string>('serverPath', 'dcd-server');
    // A bare command name (no directory component) is looked up on the
    // PATH by the OS. Anything else is resolved as a path, relative to the
    // workspace root when not absolute.
    const workspaceRoot = vscode.workspace.workspaceFolders?.[0].uri.fsPath ?? '';
    const serverPath = path.isAbsolute(serverPathSetting)
      ? serverPathSetting
      : serverPathSetting.includes(path.sep)
        ? path.join(workspaceRoot, serverPathSetting)
        : serverPathSetting;

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
    const resolvedImportPaths = (importPaths ?? []).map(p =>
      path.isAbsolute(p) ? p : path.join(workspaceRoot, p)
    );

    // Import path detection (workspace source dirs, Phobos) happens on the
    // SERVER during initialize, so any LSP client gets it — not just this
    // extension. Here we only forward user-configured paths.

    log(`importPaths sent to server: ${JSON.stringify(resolvedImportPaths)}`);
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
    };

    const client = new LanguageClient(
      'dcd-lsp',
      'D (DCD)',
      serverOptions,
      clientOptions
    );

    const context = new DcdContext(client);
    client.start().then(
      () => log('client.start() resolved — server is running'),
      (err) => log(`client.start() FAILED: ${err}`)
    );
    return context;
  }

  clientIsStarting(): boolean {
    return this.client.state === State.Starting;
  }

  dispose(): void {
    void this.client.stop();
  }
}

let dcdContext: DcdContext | undefined;

export function activate(context: vscode.ExtensionContext) {
  const outputChannel = vscode.window.createOutputChannel('DCD');
  context.subscriptions.push(outputChannel);

  context.subscriptions.push(
    vscode.commands.registerCommand('dcd.restart', async () => {
      // Restarting while the client is still starting doesn't work (the
      // client can't be stopped from the Starting state) — bail out.
      if (dcdContext?.clientIsStarting()) {
        return;
      }
      if (dcdContext) {
        dcdContext.dispose();
        dcdContext = undefined;
      }
      dcdContext = DcdContext.create(outputChannel);
      context.subscriptions.push(dcdContext);
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('dcd.shutdown', async () => {
      if (dcdContext?.clientIsStarting()) {
        return;
      }
      if (dcdContext) {
        dcdContext.dispose();
        dcdContext = undefined;
      }
    })
  );

  dcdContext = DcdContext.create(outputChannel);
  context.subscriptions.push(dcdContext);
}

export function deactivate(): Thenable<void> | undefined {
  // Normal teardown happens via context.subscriptions (VS Code disposes the
  // DcdContext, which stops the client). This is a safety net for hosts
  // that call deactivate() without disposing subscriptions.
  if (!dcdContext) {
    return undefined;
  }
  return dcdContext.client.stop();
}
