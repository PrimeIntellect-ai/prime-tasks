Better message for unused provider
Hello.
This is my first PR, if there is something wrong, please, let me know.

My code usually looks like this
```go
wire.Build(
	New,
	router.New,
	runtime.New,
)
```

When, for example, runtime becomes unused, wire returns this message
`wire.go:1:1: inject Init: unused provider "New`

Is very hard to find which dependency is unused.

There is my suggested solution.  https://github.com/google/wire/pull/162

### Additional contract requirements

- For an unused provider named `provideUnused` in package `main`, report it as `unused provider "main.provideUnused"`.
