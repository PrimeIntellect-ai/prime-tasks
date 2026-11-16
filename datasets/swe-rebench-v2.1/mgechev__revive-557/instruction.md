useless-break rule does not handle range-loops correctly
**Describe the bug**
The useless-break rule provides a specific message when a useless break is found in a switch (or select) statement inside a loop.
For example, for the following code:

```go
for {
	switch {
	case c1:
		break
	}
}
```
the rule will emit a failure: _useless break in case clause (WARN: this break statement affects this switch or select statement and not the loop enclosing it)_

The same kind of message is expected in the case of for-range loops:
```go
for _, node := range desc.Args {
	switch node := node.(type) {
	case *ast.FuncLit:
		found = true
		funcLit = node
		break // this break is useless
	}
}
```

but the rule does not emit the same message, just: _useless break in case clause_

**To Reproduce**
Steps to reproduce the behavior:
1. I updated revive `go get -u github.com/mgechev/revive`
2. I run it with the following flags & configuration file:

```shell
# flags

revive -config conf.toml testdata/useless-break.go
```

```toml
# config file
ignoreGeneratedHeader = false
severity = "warning"
confidence = 0.8
errorCode = 0
warningCode = 0

[rule.useless-break]
```

**Expected behavior**
testdata/useless-break.go:12:3: useless break in case clause
testdata/useless-break.go:21:3: useless break in case clause
testdata/useless-break.go:34:4: useless break in case clause (WARN: this break statement affects this switch or select statement and not the loop enclosing it)
**testdata/useless-break.go:43:4: useless break in case clause (WARN: this break statement affects this switch or select statement and not the loop enclosing it)**
testdata/useless-break.go:86:3: useless break in case clause
