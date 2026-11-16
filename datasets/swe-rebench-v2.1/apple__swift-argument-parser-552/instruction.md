Manual Generation: Abstracts for subcommands missing in single page mode
When I run swift package plugin generate-manual in the default single page mode, I was expecting that the resulting man page would include the abstract of the sub commands. The multi-page mode includes these in the different pages as expected. Without it, the help just has the sub command name and all it's flags (including the description for the flags) - but it doesn't help you in understanding when to use which subcommand.

**ArgumentParser version:** 1.2.2
**Swift version:** 5.7.2

### Checklist
- [x] If possible, I've reproduced the issue using the `main` branch of this package
- [x] I've searched for [existing GitHub issues](https://github.com/apple/swift-argument-parser/issues)

### Steps to Reproduce
`swift package plugin generate-manual`

### Expected behavior
Example output for a check sub-command:

```
.It Em check
Parses a ledger and prints any errors it finds
.Bl -tag -width 6n
.It Ar file
The file to parse.
.It Fl q , -quiet
Don't print errors, only indicate via exit code.
```

### Actual behavior
Example output for a check sub-command:

```
.It Em check
.Bl -tag -width 6n
.It Ar file
The file to parse.
.It Fl q , -quiet
Don't print errors, only indicate via exit code.
