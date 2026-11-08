"Pre-release versions are supported by VS Code >=1.63. Current 'engines.vscode' is '^1.64.0-insider'"
1. Have an extension declaring a minimum engine of "1.64.0-insider" in package.json
2. Run `vsce package --pre-release`
3. 🐛 Get an error implying that the extension is targeting a version of VS Code which doesn't have pre-releases

Error comes from this line: https://github.com/microsoft/vscode-vsce/blob/e53c78df45f8f160f588407d879077c4a8a9a7ab/src/package.ts#L415
