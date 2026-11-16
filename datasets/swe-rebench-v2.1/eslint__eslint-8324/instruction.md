Report format: log number of fixable problems
I'm using eslint v3.7.1.

One of my favourite eslint features is the ability to fix a lot of problems automatically. When my team considers adding a new eslint rule, we take into account how many times the rule is broken and whether those new problems can be fixed automatically. So sometimes we want to know how many problems can be automatically fixed without actually running eslint with the `--fix` option.

The current report ends with something like this:

```
✖ 103 problems (103 errors, 12 warnings)
```

It would be great if the number of fixable problems was also included. Maybe like this:

```
✖ 103 problems (103 errors, 12 warnings).
88 errors, 2 warnings can be fixed by running eslint with the --fix option.
```

### Additional contract requirements

The lint report returned by the CLIEngine (for example from `executeOnText` and `executeOnFiles`) must expose how many of the reported problems can be fixed automatically. The top-level report object and each per-file result object must include a `fixableErrorCount` property and a `fixableWarningCount` property, each a number counting the errors and warnings respectively that can be fixed automatically.

When the report contains fixable problems, the default report must append a line stating the number of fixable errors and fixable warnings in the form ``N error(s), M warning(s) potentially fixable with the `--fix` option.``. The codeframe report must append a line stating the fixable counts in the form ``N error(s) and M warning(s) potentially fixable with the `--fix` option.``, omitting any count that is zero.
