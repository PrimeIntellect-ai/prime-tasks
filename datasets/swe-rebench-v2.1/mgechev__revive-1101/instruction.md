nil panic on old go.mod (without `go` directive)
**Describe the bug**
```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x71395e]

goroutine 1 [running]:
github.com/mgechev/revive/lint.detectGoMod({0xc0005b64e0, 0x27})
	/home/powerman/go/pkg/mod/github.com/mgechev/revive@v1.5.0/lint/linter.go:176 +0x1be
github.com/mgechev/revive/lint.(*Linter).Lint(0xc000456d10, {0xc000599740, 0x1, 0x10?}, {0xc0001d4200, 0x17, 0x20}, {0x0, 0x3fe999999999999a, {0x8b2c4b, ...}, ...})
	/home/powerman/go/pkg/mod/github.com/mgechev/revive@v1.5.0/lint/linter.go:94 +0x239
github.com/mgechev/revive/revivelib.(*Revive).Lint(0xc0000d1f20, {0xc000094148, 0x1, 0x0?})
	/home/powerman/go/pkg/mod/github.com/mgechev/revive@v1.5.0/revivelib/core.go:105 +0x43f
github.com/mgechev/revive/cli.RunRevive({0x0, 0x0, 0x0})
	/home/powerman/go/pkg/mod/github.com/mgechev/revive@v1.5.0/cli/main.go:64 +0x314
main.main()
	/home/powerman/go/pkg/mod/github.com/mgechev/revive@v1.5.0/main.go:7 +0x1a
```

**To Reproduce**
Steps to reproduce the behavior:
1. I updated revive `go install github.com/mgechev/revive@latest`
2. I run it with the following flags & configuration file:

```shell
mkdir revive-old-gomod-bug
cd revive-old-gomod-bug
echo module example.com/old > go.mod
echo 'package main; func main() {println("ok")}' > main.go
go run .
# Output:
# ok
revive ./...
# it panics
```

```toml
# no config
```

**Expected behavior**
It should not panic on outdated (but valid) projects.

**Desktop (please complete the following information):**
 - OS: Gentoo Linux
 - go version go1.23.2 linux/amd64

**Additional context**
`go mod tidy` adds `go` directive to `go.mod` and this fixes the panic.
