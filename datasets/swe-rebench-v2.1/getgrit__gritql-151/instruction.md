Error message when pattern name contains invalid characters is confusing
The error message that comes out when a pattern name contains a `-` is confusing and not helpful

Reproducer:
`grit.yaml`
```yaml
patterns:
  - name: use-winston
    level: error
    body: |
      `console.log($msg)` => `winston.log($msg)` where {
        $msg <: not within or { `it($_, $_)`, `test($_, $_)`, `describe($_, $_)` }
      }
```

Run:
```
$ grit apply use-winston
Your working tree currently has untracked changes and Grit will rewrite files in place. Do you want to proceed? yes
ERROR (code: 299) - Pattern syntax error at 1:1. If you hit this error while running grit apply on a pattern from the Grit standard library, try running grit init. If you are running a custom pattern, check out the docs at https://docs.grit.io/ for help with writing patterns.
```

### Additional contract requirements

- When `grit apply` is run for the invalid pattern name `test-bad`, stderr must be: `Error: Invalid pattern name: test-bad. Grit patterns must match the regex /[\^#A-Za-z_][A-Za-z0-9_]*/. For more info, consult the docs at https://docs.grit.io/guides/patterns#pattern-definitions.`
