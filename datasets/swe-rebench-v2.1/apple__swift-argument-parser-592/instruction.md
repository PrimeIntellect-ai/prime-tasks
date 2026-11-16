Nested option groups don't show titles/organization in help text
An option group that contains other option groups loses the inner organization and becomes a flat list in the help text.

Sometimes it makes sense to break down a list of flags, options, and arguments that belong together into smaller option groups so that they are nicely grouped and labeled in the help text.

If these option groups are used by multiple commands it would be nice to create an option group of all of them and use that in both commands. However, doing so loses the inner labels and groups of the nested option groups.

In the extreme case of this where one command support a superset of another command it's nice to be able to define an option group that is the subset command. However, if the subset command has its options organized into groups, all that organization is lost in the superset command.

**ArgumentParser version:** `1.2.2`
**Swift version:** swift-driver version: 1.87.1 Apple Swift version 5.9 (swiftlang-5.9.0.128.108 clang-1500.0.40.1)

### Checklist
- [x] If possible, I've reproduced the issue using the `main` branch of this package
- [x] I've searched for [existing GitHub issues](https://github.com/apple/swift-argument-parser/issues)

### Steps to Reproduce

Define these parsable arguments and inspect the help text for the `repeat` command.

```swift
import ArgumentParser

@main
struct Repeat: ParsableCommand {
    @OptionGroup()
    var options: BothOptions
}

struct CountOptions: ParsableArguments {
    @Flag(help: "Include a counter with each repetition.")
    var includeCounter = false

    @Option(name: .shortAndLong, help: "The number of times to repeat 'phrase'.")
    var count: Int? = nil
}

struct PhraseOptions: ParsableArguments {
    @Argument(help: "The phrase to repeat.")
    var phrase: String

    @Argument(help: "An alternate phrase to repeat every other time.")
    var alternatePhrase: String?
}

struct BothOptions: ParsableArguments {
    @OptionGroup(title: "Phrase options")
    var phraseOptions: PhraseOptions

    @OptionGroup(title: "Count options")
    var countOptions: CountOptions
}
```

### Expected behavior

I would expect the option group organization from `BothOptions` to be represented in the help text
```
USAGE: repeat <phrase> [<alternate-phrase>] [--include-counter] [--count <count>]

PHRASE OPTIONS:
  <phrase>                The phrase to repeat.
  <alternate-phrase>      An alternate phrase to repeat every other time.

COUNT OPTIONS:
  --include-counter       Include a counter with each repetition.
  -c, --count <count>     The number of times to repeat 'phrase'.

OPTIONS:
  -h, --help              Show help information.
```

### Actual behavior

The option group organization is lost, making the actual help text

```
USAGE: repeat <phrase> [<alternate-phrase>] [--include-counter] [--count <count>]

ARGUMENTS:
  <phrase>                The phrase to repeat.
  <alternate-phrase>      An alternate phrase to repeat every other time.

OPTIONS:
  --include-counter       Include a counter with each repetition.
  -c, --count <count>     The number of times to repeat 'phrase'.
  -h, --help              Show help information.
```
