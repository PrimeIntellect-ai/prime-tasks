Validate any declared main/browser entrypoints are in the final vsix.
[feat: sanity check to validate entrypoints#669](https://github.com/microsoft/vscode-vsce/pull/669)

I managed to refactor my 'out' to 'dist', not noticing 'dist' was in my .vscodeignore.  All that testing, but my poblished package had no entrypoints for a few hours.

Lame mistake - yeah.  But with 2 potential entrypoints and the refactoring people will be doing to support the web context, I think it's possible others may miss one of their entrypoints.  Regardless - it's a very easy sanity check and I've provided a potential PR.

### Additional contract requirements

- If a declared entrypoint is missing, the error message must contain `entrypoint(s) missing` and the missing entrypoint path.
