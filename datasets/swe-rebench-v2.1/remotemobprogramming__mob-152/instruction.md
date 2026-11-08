Did we intend to deprecate older Go versions and rename the executable to `mob.sh`?
While touch-testing #121 today it took me several confusing minutes to figure out why none of the new features were showing up in `mob`, and after a lot of thrashing around I finally realized my `mob` executable wasn't rebuilding when I ran `go build`.  I finally found this in go.mod, last modified in 878661c5:

```
module mob.sh

go 1.16
```

That causes `go build` to build an executable named `mob.sh`, which will cause these issues:

- an `.sh` suffix implies a shell script -- my eyes didn't spot it as a Go executable
- the name change from `mob` to `mob.sh` breaks a buncha local code that assumes the executable is named `mob`
- the new name disagrees with examples in the README

The upgrade from version 1.15 to 1.16 is also puzzling me -- the code builds and the tests pass in our org's 1.14.2 environment, though I admit I may be missing something, and I didn't try this in a fresh Go 1.14.2 install with an empty local package cache 'cause I'm busy today digging into #121.  Did we bump that version number because of requirements that need 1.16 features?

### Additional contract requirements

- Running `go build` in the repository root must produce an executable named `mob`, not `mob.sh`.
- The project must declare Go 1.14 as its minimum Go language version (not 1.16).
