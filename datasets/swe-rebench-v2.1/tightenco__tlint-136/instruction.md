tlint always returns an error when using `--json`
Hi,

As part of a review on an [issue](https://github.com/d9705996/vscode-tighten-lint/issues/2) for the VSCode integration I have noticed a change in behaviour of the `--json` flag since [v3.0.9](https://github.com/tightenco/tlint/compare/v3.0.8...v3.0.9).

[HIDDEN]   In the extension if the return code of the tlint command is not `0` then the output isn't processed as it is assumed the command failed.

I can change the behaviour of the extension to ignore the error but since the json format is mostly useful for IDE integration [HIDDEN] and allow the consumer to parse the JSON object that is always returned to identify whether there are any linting errors.

Is there any reason for the change in behaviour that I am missing?  Otherwise happy to add a PR to change the return value.

### Additional contract requirements

- When `--json` is used, the command must return a success status (0) whether or not lint findings are present.
