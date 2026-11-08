Custom linters have nil PartitionStrategy
Using the following config produces the following error.
[HIDDEN]

```json
{
  "Linters": { "license": "grep -rL 'Apache License' {path}:^(?P<path>.*?\\.go.*)"},
  "Severity": {"license": "error"},
  "Enable": ["license"]
}
```

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x11ef957]

goroutine 1 [running]:
main.(*linterState).Partitions(0xc4201084b0, 0xc4201084b0, 0xc420049dd0, 0xc420096208, 0xc420010240, 0xc4200123e0)
        /go/src/github.com/alecthomas/gometalinter/execute.go:85 +0xb7
main.runLinters(0xc4201a7bc0, 0xc4200bb400, 0x28, 0x28, 0x8, 0x0, 0x0, 0x28, 0x28)
        /go/src/github.com/alecthomas/gometalinter/execute.go:126 +0xad8
main.main()
        /go/src/github.com/alecthomas/gometalinter/main.go:179 +0x39e

```

### Additional contract requirements

- A custom linter configuration that does not specify a partition strategy must be able to proceed through partitioning without a nil-pointer panic.
