swc_ecma_codegen emits `/` in some mapped types
### Describe the bug

I'm using swc_ecma_codegen directly to emit a .d.ts file.  It should look like this:
```
declare type Custom<A> = {
    -readonly [P in keyof A]+?: A[P];
}
```
but the actual output was:
```
declare type Custom<A> = {
    -readonly [P in keyof A]+/: A[P];
}
```


### Input code

_No response_

### Config

_No response_

### Playground link

_No response_

### Expected behavior

The following should be output

### Actual behavior

_No response_

### Version

swc_ecma_codegen = 0.127.16

### Additional context

[HIDDEN]  I can work on a PR for this.

### Additional contract requirements

- When emitting a mapped type with the `+?` optional modifier, output `+?`, not `+/`.
