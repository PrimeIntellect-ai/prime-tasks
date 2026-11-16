https://github.com/benbjohnson/clock is EOL/archived.
**Describe the bug**
https://github.com/benbjohnson/clock is archived.

**To Reproduce**
N/A, we can code scanning tools in-house that complain about archived repo (considered EOL)

**Expected behavior**
N/A, code scanning shouldn't complain about `go.mod`.

**Additional context**
based on https://github.com/benbjohnson/clock/network maybe https://github.com/itbasis/go-clock would be a good in-place replacement.

```
╰─ go mod graph | grep github.com/benbjohnson/clock
go.uber.org/fx@v1.20.0 github.com/benbjohnson/clock@v1.3.0
go.uber.org/zap@v1.24.0 github.com/benbjohnson/clock@v1.1.0
go.uber.org/zap@v1.18.1 github.com/benbjohnson/clock@v1.1.0
go.uber.org/zap@v1.19.0 github.com/benbjohnson/clock@v1.1.0
```

### Additional contract requirements

Fx's Go module dependency graph, including transitive dependencies, must not contain `github.com/benbjohnson/clock`.
