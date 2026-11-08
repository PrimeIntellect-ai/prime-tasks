Panic in Simpleworker
Hello,

I'm getting panic in Debug logger when a simple worker completes the job
```
level=debug time="2022-04-17T22:20:12Z" msg="completed job %!s(PANIC=String method: runtime error: invalid memory address or nil pointer dereference)
```

That's the [culprit](https://github.com/gobuffalo/buffalo/blob/main/worker/simple.go#L103) and this  [code panics too](https://github.com/gobuffalo/buffalo/blob/main/worker/simple.go#L81)

### Additional contract requirements

When a Simpleworker completes a job with debug logging enabled, logging the completion must not panic. When a Simpleworker begins performing a job with debug logging enabled, logging the job must not panic.
