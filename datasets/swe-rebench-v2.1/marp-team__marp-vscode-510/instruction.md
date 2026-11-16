The exported result is incorrect if the document had not UTF-8 encoding
### Version of Marp Tool

Marp for VS Code v3.1.0

### Operating System

macOS

### Environment

OS version: macOS Sequoia 15.3.1
VS Code version (Marp for VS Code): VS Code 1.97.2

### How to reproduce

1. Create a new Markdown file just like this:

```
🐣
```

2. Save Markdown file with UTF-16 LE encoding
3. Export slide deck to any format.

### Expected behavior

Show a slide page with the content `🐣`

### Actual behavior

A slide page has incorrect encoding.

### Additional information

Originally reported in marp-team/marp#558.

Extension could not deal with that due to lack of VS Code API for getting a encoding for the current document. But now the latest VS Code 1.98 has a newly proposed API for getting encoding.
https://code.visualstudio.com/updates/v1_98#_text-encodings
https://github.com/microsoft/vscode/blob/501ee833b16b8e83ba656c46e0888aadd9d2db04/src/vscode-dts/vscode.proposed.textDocumentEncoding.d.ts#L1

[HIDDEN]
https://github.com/marp-team/marp-vscode/blob/bc09bd5241c28889ec077a7820992599a0e307cd/src/marp-cli.ts#L30

### Additional contract requirements

- The current document exposes its text encoding through the VS Code `TextDocument.encoding` field. Its value is a string such as `'utf8'`, `'utf8bom'`, or `'utf16le'`.
- Exporting a clean file-backed document with a non-UTF-8 encoding must use a separate temporary input file containing the document's text, rather than passing the original saved file as input.
- The temporary input file is removed when its cleanup operation is invoked.
