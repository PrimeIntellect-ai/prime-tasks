Unclear help with sets of 3 or more mutually exclusive flags
I defined a set of mutually exclusive flags thusly:
```
enum OutputBehaviour: String, CaseIterable { case stats, count, list }

struct Options: ParsableCommand {
  @Flag(help: "Program output")
  var behaviour: OutputBehaviour
}

let options = Options.parseOrExit()
```

The help message that corresponds to these is not very helpful:
```
$ ./options --help
USAGE: options --stats --count --list

OPTIONS:
  --stats/--count         Program output
  --list                  Program output
  -h, --help              Show help information.
```

The help generator lists them in pairs whenever there are more than 2.
It's not clear that the three flags (stats, count, list) are a set.
It's not clear that they are mutually exclusive.

### Additional contract requirements

- For an enum flag with cases `stats`, `count`, and `list`, declared with `@Flag(name: .shortAndLong, help: "Change the program output")`, help must list all three long forms in usage and show all three short/long name pairs together as one option entry, with the supplied description.
- For an enum flag with cases `stats`, `count`, and `list`, declared with `@Flag(name: .short, default: .list, help: "Change the program output")`, help must show all three short forms as optional usage arguments and group them together in one option entry, with the supplied description.
