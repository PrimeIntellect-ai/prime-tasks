VS Code v1.58 does not open Workspace Trust from a notification of export command
### Version of Marp Tool

Marp for VS Code v1.1.0

### Operating System

macOS

### Environment

- OS version: macOS Big Sur 11.4
- VS Code version: VS Code 1.58.0


### How to reproduce

1. Open Marp Markdown in restricted mode
2. Choose `markdown.marp.export` from the command palette.
3. Click "Manage Worksapce Trust..." in a notification.

![](https://user-images.githubusercontent.com/3993388/124985679-a5a85500-e075-11eb-88f0-94ed7c124002.png)



### Expected behavior

Open "Workspace Trust" panel.

### Actual behavior

Nothing.

### Additional information

### Output in developer console

```
workbench.desktop.main.js:sourcemap:62 [Extension Host] rejected promise not handled within 1 second: Error: command 'workbench.action.manageTrust' not found (at /Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/out/vs/workbench/services/extensions/node/extensionHostProcess.js:103:30190)
m @ workbench.desktop.main.js:sourcemap:62
workbench.desktop.main.js:sourcemap:62 [Extension Host] stack trace: Error: command 'workbench.action.manageTrust' not found    at g._tryExecuteCommand (vscode-file://vscode-app/Applications/Visual%20Studio%20Code%20-%20Insiders.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js:1678:3360)    at vscode-file://vscode-app/Applications/Visual%20Studio%20Code%20-%20Insiders.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js:1678:3241    at processTicksAndRejections (internal/process/task_queues.js:93:5) (at /Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/out/vs/workbench/services/extensions/node/extensionHostProcess.js:103:30269)
m @ workbench.desktop.main.js:sourcemap:62
workbench.desktop.main.js:sourcemap:627   ERR command 'workbench.action.manageTrust' not found: Error: command 'workbench.action.manageTrust' not found
    at g._tryExecuteCommand (vscode-file://vscode-app/Applications/Visual%20Studio%20Code%20-%20Insiders.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js:1678:3360)
    at vscode-file://vscode-app/Applications/Visual%20Studio%20Code%20-%20Insiders.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js:1678:3241
    at processTicksAndRejections (internal/process/task_queues.js:93:5)
```
