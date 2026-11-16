Support aliases for all switches
Currently it seams the `aliases` tag only works for "commands", would it be possible to enable it for normal flags as well?

```go
type Arg struct {
    TestFlag string `kong:"aliases='alt-flag'"
}
```

That would let you either run `./cmd --test-flag blah` or `./cmd --alt-flag blah` and in both cases the `TestFlag` field would contain `blah`.  Maybe this is already allowed and I'm just doing it wrong but in testing it says the aliases names are an "unknown flag".

### Additional contract requirements

- For an anonymous struct where `Flag2` has the alias `flag`, if `flag` duplicates either the alias or flag name of `Flag1`, `kong.New` must return exactly `<anonymous struct>.Flag2: duplicate flag --flag`.
