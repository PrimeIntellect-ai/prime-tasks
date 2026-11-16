SencBox.Size() can panic with non-zero SampleCount and empty rawData
I discovered this while fuzzing in #397 but didn't know how to fix it.

```
--- FAIL: FuzzDecodeBox (0.04s)
    --- FAIL: FuzzDecodeBox/75565444c6c2f1dd (0.00s)
panic: runtime error: index out of range [0] with length 0 [recovered]
	panic: runtime error: index out of range [0] with length 0

goroutine 359 [running]:
testing.tRunner.func1.2({0x1046cfd80, 0x140000261c8})
	/opt/homebrew/Cellar/go/1.23.1/libexec/src/testing/testing.go:1632 +0x1bc
testing.tRunner.func1()
	/opt/homebrew/Cellar/go/1.23.1/libexec/src/testing/testing.go:1635 +0x334
panic({0x1046cfd80?, 0x140000261c8?})
	/opt/homebrew/Cellar/go/1.23.1/libexec/src/runtime/panic.go:785 +0x124
github.com/Eyevinn/mp4ff/mp4.(*SencBox).Size(0x0?)
	/Users/eric/src/mp4ff/mp4/senc.go:266 +0xb0
github.com/Eyevinn/mp4ff/mp4.FuzzDecodeBox.func1(0x1400012e820, {0x140004ca610, 0x10, 0x10})
	/Users/eric/src/mp4ff/mp4/fuzz_test.go:73 +0xc4
```

There is currently a skipped test in that pull request that can replicate the issue with commenting out the `Skip()` and then running:

```
go test -run=FuzzDecodeBox/75565444c6c2f1dd ./mp4
```
