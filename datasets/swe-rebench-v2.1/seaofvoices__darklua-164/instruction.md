Avoid `unable to obtain parent directory from ""` error for certain paths
When providing a sourcemap as a path like `sourcemap.json` which is relative to the directory containing the darklua configuration file, this error is thrown:

```
unable to obtain parent directory from ``
```

To fix it, the user has to provide the path as `./sourcemap.json`. Darklua can simplify this and adjust its relative path logic to assume that the parent path of `sourcemap.json` is `.`
