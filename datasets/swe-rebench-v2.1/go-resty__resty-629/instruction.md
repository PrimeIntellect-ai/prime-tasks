`jitterBackoff` Panic When max = 1 ns
Setting max timeout of 1 ns (`time.Duration(1) * time.Nanosecond`) can cause the `jitterBackoff` function panic.
```
panic: invalid argument to Int63n [recovered]
        panic: invalid argument to Int63n

goroutine 37 [running]:
testing.tRunner.func1.2({0x1040b2f80, 0x10433ee98})
        /opt/homebrew/Cellar/go/1.20.1/libexec/src/testing/testing.go:1526 +0x1c8
testing.tRunner.func1()
        /opt/homebrew/Cellar/go/1.20.1/libexec/src/testing/testing.go:1529 +0x364
panic({0x1040b2f80, 0x10433ee98})
        /opt/homebrew/Cellar/go/1.20.1/libexec/src/runtime/panic.go:884 +0x1f4
math/rand.(*Rand).Int63n(0xe?, 0x140002615a8?)
        /opt/homebrew/Cellar/go/1.20.1/libexec/src/math/rand/rand.go:121 +0xe8
github.com/go-resty/resty/v2.randDuration(0x0)
        /Users/myusername/dev/resty/retry.go:215 +0xd8
github.com/go-resty/resty/v2.jitterBackoff(0xb2d05e00, 0x1, 0x6?)
        /Users/myusername/dev/resty/retry.go:198 +0xb0
github.com/go-resty/resty/v2.sleepDuration(0x14000379540?, 0xb2d05e00, 0x0?, 0x102f1c044?)
        /Users/myusername/dev/resty/retry.go:178 +0xa8
github.com/go-resty/resty/v2.Backoff(0x14000261870, {0x14000261848, 0x5, 0x1400078d1c8?})
        /Users/myusername/dev/resty/retry.go:139 +0x288
...
```
