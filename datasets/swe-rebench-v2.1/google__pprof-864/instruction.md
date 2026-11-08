panics if profile is not found
Hello! I opened https://github.com/golang/go/issues/67626 for the Go project to track consuming a fix; my guess is there should be an issue on this project to track creation of a fix.

### What version of pprof are you using?

I've checked out 9665fa269a300a7e802154f4df8c4e9ee970fc5c from May 20, currently the latest version of the `main` branch.

### What operating system and processor architecture are you using?

linux/amd64

### What did you do?

```
$ go run . ./missing
```

### What did you expect to see?

```
$ go run . ./missing
./missing: open ./missing: no such file or directory
pprof: failed to fetch any source profiles
exit status 2
```

### What did you see instead?

```
$ go run . ./missing
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x8906f7]

goroutine 19 [running]:
github.com/google/pprof/internal/driver.fetch({0x7fffec08a721, 0x9}, 0xffffffffc4653600, 0xffffffffc4653600, {0x7fc040045278, 0xc000080210}, {0xa68860, 0xc0000aa840})
	/home/rhysh/pprof/internal/driver/fetch.go:514 +0x2f7
github.com/google/pprof/internal/driver.grabProfile(0xc0001e28c0, {0x7fffec08a721?, 0x0?}, {0x0?, 0x0?}, {0xa69c80, 0xc000032fd0}, {0x7fc040045278, 0xc000080210}, {0xa68860, ...})
	/home/rhysh/pprof/internal/driver/fetch.go:334 +0x131
github.com/google/pprof/internal/driver.concurrentGrab.func1(0xc000234000)
	/home/rhysh/pprof/internal/driver/fetch.go:211 +0x86
created by github.com/google/pprof/internal/driver.concurrentGrab in goroutine 34
	/home/rhysh/pprof/internal/driver/fetch.go:209 +0x8f
exit status 2
```

Bisect says " a5a03c77bf0842e0592d2be8129bca0b2bd3bb60 is the first bad commit".

CC @cuishuang, @aalexand
