"identity" meta hook
Pretty often I or a bug reporter reaches for the "simplest hook possible" -- often to debug what files are being passed through.

Let's add an "identity" hook which does the following:

1. Is always verbose
2. prints the filenames passed to it
3. Always succeeds

Basically make something like this, but without depending on "actual" `echo`:

```yaml
-   id: identity
    name: identity
    entry: echo
    verbose: true
    language: system
```

### Additional contract requirements

- The hook is exposed as a public function `main(argv=None)` in the module
  `pre_commit.meta_hooks.identity`. When `argv` is omitted, the function uses the
  command-line arguments supplied after the program name. Each element of `argv` is
  written as its own line, and the function returns `None`.
- The meta hook is registered under the id `identity` and is always verbose.
