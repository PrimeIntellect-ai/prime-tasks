index out of range error when using multiline commit messages
**Describe the bug**
Multi-line commit messages don't work and lead to the following error

```
panic: runtime error: index out of range [2] with length 2

goroutine 1 [running]:
github.com/lindell/multi-gitter/cmd.run(0xc000191b80, {0xc0001ec180, 0x4, 0x4})
	/home/runner/work/multi-gitter/multi-gitter/cmd/cmd-run.go:112 +0xe5e
github.com/spf13/cobra.(*Command).execute(0xc000191b80, {0xc0001ec140, 0x4, 0x4})
	/home/runner/go/pkg/mod/github.com/spf13/cobra@v1.2.1/command.go:856 +0x60e
github.com/spf13/cobra.(*Command).ExecuteC(0xc000191900)
	/home/runner/go/pkg/mod/github.com/spf13/cobra@v1.2.1/command.go:974 +0x3bc
github.com/spf13/cobra.(*Command).Execute(...)
	/home/runner/go/pkg/mod/github.com/spf13/cobra@v1.2.1/command.go:902
main.main()
	/home/runner/work/multi-gitter/multi-gitter/main.go:19 +0xe5
Error: panic: runtime error: index out of range [2] with length 2
```

**To Reproduce**
Steps to reproduce the behavior:

```
multi-gitter run 'echo "something"' --repo some/repo --branch some-branch --commit-message $'foo\nbar'
```

or via config.yaml:
```
commit-message: |
  foo
  bar
```

**Expected behavior**
There is no error

**Additional context**
v0.38.2 on Mac
