Unable to scan npm packages within a namespace (e.g. @typescript-eslint/eslint-plugin)
```
Found 0 potentially malicious indicators scanning @typescript-eslint/eslint-plugin version 5.29.0

Some rules failed to run while scanning @typescript-eslint/eslint-plugin version 5.29.0:

* download-package: [Errno 2] No such file or directory: '/var/folders/_j/rxmxz87j51q5mzmk79qs0qs00000gp/T/tmpzdw3l0u8/@typescript-eslint/eslint-plugin.tgz'
```

### Additional contract requirements

The scanner must successfully download and analyze scoped npm packages (for example, `@typescript-eslint/eslint-plugin`) rather than report a download-package failure.
