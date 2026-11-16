Description with default value but no abstract begins with an extra space
If a user chooses to not include an abstract, the default value will begin with an extra space, resulting vertically unaligned descriptions, example:

```swift
struct Example: ParsableCommand {
    @Option(help: "The first option")
    var one: Bool
    @Option(default: "42")
    var two: String
    @Option(help: "The third option")
    var three: String
}
```

gets the following generated help text:

```
USAGE: example --one <one> [--two <two>] --three <three>

OPTIONS:
  --one <one>             The first option
  --two <two>              (default: 42)
  --three <three>         The third option
  -h, --help              Show help information.
```

Note description for `two` is unaligned vertically in relation to that of `one` and `three`
