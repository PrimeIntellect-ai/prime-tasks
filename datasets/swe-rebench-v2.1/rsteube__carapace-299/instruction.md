context.Args contains curently completed word
```sh
git tag <TAB>
```

`context.Args` contains the current callback value (`[]string{""}`) but should be empty.

### Additional contract requirements

- When there are no preceding arguments, `context.Args` must be a non-nil empty slice (`[]string{}`), not `nil`.
