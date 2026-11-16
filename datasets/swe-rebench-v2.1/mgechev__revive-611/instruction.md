Crash in revive - when using master branch - happens after commit 0fada9d76c4319e446514f2df0a3cd819c88f58d
**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. I updated revive `go get -u github.com/mgechev/revive`
2. I run it with the following flags & configuration file:

```shell
# flags

revive -formatter friendly -exclude ./vendor/... -exclude rlang/rlang.peg.go ./...
```

**Expected behavior**
it should not crash at least

**Logs**
```
	[HIDDEN]
go/ast.Walk({0x137ffc0, 0xc0046c47a0}, {0x1385668, 0xc000490e80})
	/Users/gburanov/.asdf/installs/golang/1.17/go/src/go/ast/walk.go:50 +0x5f
go/ast.walkExprList({0x137ffc0, 0xc0046c47a0}, {0xc0004a2440, 0x1, 0xc0004ac300})
	/Users/gburanov/.asdf/installs/golang/1.17/go/src/go/ast/walk.go:24 +0x87
go/ast.Walk({0x137ffc0, 0xc0046c4780}, {0x1385b90, 0xc0004a5600})
	/Users/gburanov/.asdf/installs/golang/1.17/go/src/go/ast/walk.go:217 +0x124f
go/ast.walkStmtList({0x137ffc0, 0xc0046c4780}, {0xc0004a2450, 0x1, 0xc0004ac300})
	/Users/gburanov/.asdf/installs/golang/1.17/go/src/go/ast/walk.go:30 +0x87
go/ast.Walk({0x137ffc0, 0xc0046c4360}, {0x1385618, 0xc000492a50})
	/Users/gburanov/.asdf/installs/golang/1.17/go/src/go/ast/walk.go:225 +0xedf
go/ast.Walk({0x137ffc0, 0xc0045ea0c0}, {0x13858e8, 0xc000492a80})
	/Users/gburanov/.asdf/installs/golang/1.17/go/src/go/ast/walk.go:346 +0x7dc
go/ast.walkDeclList({0x137ffc0, 0xc0045ea0c0}, {0xc0004c0000, 0xb, 0xc0002cfad0})
	/Users/gburanov/.asdf/installs/golang/1.17/go/src/go/ast/walk.go:36 +0x87
go/ast.Walk({0x137ffc0, 0xc0045ea0a0}, {0x1385898, 0xc0004ac300})
	/Users/gburanov/.asdf/installs/golang/1.17/go/src/go/ast/walk.go:355 +0x15c5
github.com/mgechev/revive/rule.(*ErrorStringsRule).Apply(0x12d3780, 0xc000491e40, {0x1320d57, 0xd, 0x1})
	/Users/gburanov/gocode/src/github.com/mgechev/revive/rule/error-strings.go:44 +0x23a
github.com/mgechev/revive/lint.(*File).lint(0xc000491e40, {0xc0002b2400, 0x25, 0x40}, {0x0, 0x3fe999999999999a, {0xc000128e48, 0x5}, 0x0, 0xc0001ae120, ...}, ...)
	/Users/gburanov/gocode/src/github.com/mgechev/revive/lint/file.go:107 +0x1ea
github.com/mgechev/revive/lint.(*Package).lint.func1(0x0)
	/Users/gburanov/gocode/src/github.com/mgechev/revive/lint/package.go:173 +0x85
created by github.com/mgechev/revive/lint.(*Package).lint
	/Users/gburanov/gocode/src/github.com/mgechev/revive/lint/package.go:172 +0xb1
```
