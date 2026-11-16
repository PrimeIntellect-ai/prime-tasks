Repeated flag causes error in some cases
When repeating a flag defined from a mutually-exclusive set, one gets an error.
```
enum Enum: String, CaseIterable { case s, t, u }

struct Options: Parsable Command {
  @Flag(name: .short, exclusivity: .exclusive, help: "Help!")
  var flag: Enum
}

let options = Options.parseOrExit()
```
```
$ options -s -s
Error: Value to be set with flag '-s' had already been set with flag '-s'
Usage: options -s -t -u
```

Should repetition in such a case simply be ignored?

### Additional contract requirements

- For a flag configured with `.exclusive` whose value is selected from a mutually exclusive set, supplying the same member more than once must succeed without a duplicate-value error, and the parsed value must remain that member.
