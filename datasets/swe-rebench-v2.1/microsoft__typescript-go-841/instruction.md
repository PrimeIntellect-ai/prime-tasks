`--watch` assumes a config file exists, crashes if not
```
mkdir foo
cd foo
touch index.ts
../built/local/tsgo.exe tsc index.ts --watch
```

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal 0xc0000005 code=0x0 addr=0x20 pc=0x7ff6fde2bc94]

goroutine 1 [running]:
github.com/microsoft/typescript-go/internal/execute.createWatcher(...)
        D:/typescript-go/internal/execute/watcher.go:28
github.com/microsoft/typescript-go/internal/execute.executeCommandLineWorker({0x7ff6fe128bf0, 0x4000112a00}, 0x0, 0x4000064680)
        D:/typescript-go/internal/execute/tsc.go:125 +0x5b4
github.com/microsoft/typescript-go/internal/execute.CommandLine({0x7ff6fe128bf0, 0x4000112a00}, 0x0, {0x40000640a0?, 0x2?, 0x2?})
        D:/typescript-go/internal/execute/tsc.go:18 +0x7c
main.runMain()
        D:/typescript-go/cmd/tsgo/main.go:136 +0x174
main.main()
        D:/typescript-go/cmd/tsgo/main.go:126 +0x1c

### Additional contract requirements

- For `tsc index.ts --watch` with an empty `index.ts` and no config file, the command must produce no output.
