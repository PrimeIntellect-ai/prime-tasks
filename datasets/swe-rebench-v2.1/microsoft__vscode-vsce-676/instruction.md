vsce package, Extension entrypoint(s) missing
(Happy New Year!)

The GitHub CI of my vscode extension has been working very well for a long time (vsce v1.x). However, it doesn't seem to work with vsce v2.x and says

```
 ERROR  Extension entrypoint(s) missing. Make sure these files exist and aren't ignored by '.vscodeignore':
  extension/out/src/extension
```

I'm a little confused. Is there any API change? Guess it may be related to the VS Code Web but I haven't got time to take a closer look.

---

### Additional information

the `package.json`
https://github.com/yzhang-gh/vscode-dic-completion/blob/master/package.json

the ci file
https://github.com/yzhang-gh/vscode-dic-completion/blob/master/.github/workflows/main.yml

the failed ci log
https://github.com/yzhang-gh/vscode-dic-completion/runs/4679563201?check_suite_focus=true

```
+ vsce@2.6.0

Run vsce package
Executing prepublish script 'npm run vscode:prepublish'...

> dictionary-completion@1.1.2 vscode:prepublish /home/runner/work/vscode-dic-completion/vscode-dic-completion
> tsc -p ./

 ERROR  Extension entrypoint(s) missing. Make sure these files exist and aren't ignored by '.vscodeignore':
  extension/out/src/extension
```

the past passed ci log
https://github.com/yzhang-gh/vscode-dic-completion/runs/3868473421?check_suite_focus=true

```
+ vsce@1.100.1

Run vsce package
Executing prepublish script 'npm run vscode:prepublish'...

> dictionary-completion@1.1.1 vscode:prepublish /home/runner/work/vscode-dic-completion/vscode-dic-completion
> tsc -p ./

 DONE  Packaged: /home/runner/work/vscode-dic-completion/vscode-dic-completion/dictionary-completion-1.1.1.vsix (13 files, 79.63KB)
```

### Additional contract requirements

When an extension declares an entrypoint without a `.js` suffix, packaging must resolve it to the corresponding `.js` file. The entrypoint must still be rejected as missing if that corresponding file is not included in the package.
