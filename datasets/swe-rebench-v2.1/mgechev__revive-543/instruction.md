revive:disable-next-line isn't working
Using macOS and golangci-lint v1.41.1 (a207480, 2021-06-19), I expected this to work, and not give me a linter failure:
```go
//revive:disable-next-line:var-naming
func (source Source) BaseApiURL() string {
```

But actually I get this error when linting:
```
source.go:99:22: var-naming: method BaseApiURL should be BaseAPIURL (revive)
func (source Source) BaseApiURL() string {
                     ^
make: *** [lint] Error 1
```

To work around, I can use this:
```go
func (source Source) BaseApiURL() string { //revive:disable-line:var-naming
```

But from how `disable-next-line` is described in the README, I think I've seen a bug.
