panic when passing -q flag
I mistakenly tried to use `-q` instead of `-quiet` (forgetting the usage). Instead of being told of the bad flag, nancy instead panicked.

```
panic: runtime error: slice bounds out of range [:5] with length 2

goroutine 1 [running]:
github.com/sonatype-nexus-community/nancy/logger.init.0()
	/home/jake/go/pkg/mod/github.com/sonatype-nexus-community/nancy@v0.1.11/logger/logger.go:35 +0x1c5
```

Forgive my deletion of the template; it seemed like a feature request template whereas this is a bug.

I'm on `v0.1.11`.

cc @bhamail / @DarthHater

### Additional contract requirements

- Passing an unrecognized command-line flag (for example `-q`) must not panic; the offending flag must be reported and the program must exit with a non-zero status.
