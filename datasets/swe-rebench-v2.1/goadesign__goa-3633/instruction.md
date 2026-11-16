Allow specifying protoc command
**Goal:** To reduce onboarding and setup I want to be able to run `go generate ./...` in a newly cloned project and have that work without any other dependencies other than the correct Go version. I also want to keep versions pinned (using go.mod if possible). For goa I can accomplish that by including a go generate comment like the following. This also ensures my project's goa matches the code generator when maintaining many goa-based projects.

```go
//go:generate go run goa.design/goa/v3/cmd/goa gen ...
```

**Problem**: If goa needs to launch `protoc` to generate gRPC, the developer must have `protoc` installed and the two plugins that goa uses must be in protoc's path. I've been able to get around this by creating a wrapper script that can download the correct version of `protoc` from GitHub into a cache directory and `go install` the plugins into that same directory, then execute goa with its `PATH` prefixed with that directory. Special care must be taken to ensure this works across Windows/Mac/Linux.

**Solution**: Add a new flag to specify the command to run for protoc. I created https://github.com/duckbrain/goprotoc This is a `go run`able drop-in replacement for `protoc` that will also use `go run` for plugins, You could use  `-protoc "go generate github.com/duckbrain/goprotoc"` (and [soon](https://tip.golang.org/doc/modules/managing-dependencies#tools) `"go tool goprotoc"`) to get a zero dependency go generate with goa.

### Additional contract requirements

For gRPC schema generation, a developer can select a protoc-compatible command with `Meta("protoc:cmd", ...)`; the first value names the command and subsequent values are prepended arguments. The selected command may be launched through Go, such as with `go run`. When no alternate command is configured, Goa continues to invoke the standard `protoc` command.
