Repeated flags with FlagExclusivity.chooseFirst error instead of choosing first.
<!--
    Thanks for contributing to the Swift Argument Parser!

    Before you submit your issue, please replace each paragraph
    below with the relevant details for your bug, and complete
    the steps in the checklist by placing an 'x' in each box:

    - [x] I've completed this task
    - [ ] This task isn't completed
-->

Repeated flags defined with `FlagExclusivity.chooseFirst` error instead of choosing first.

**ArgumentParser version:** `master` at https://github.com/apple/swift-argument-parser/commit/58660b05c444b6916df980e7ad1e8f047cf14977
**Swift version:** Apple Swift version 5.2 (swiftlang-1103.0.30 clang-1103.0.30)

### Checklist
- [x] If possible, I've reproduced the issue using the `master` branch of this package
- [x] I've searched for [existing GitHub issues](https://github.com/apple/swift-argument-parser/issues)

### Steps to Reproduce
Use this simple program:
```
enum Enum: String, CaseIterable { case s, t, u }

struct Options: ParsableCommand {
  @Flag(name: .short, exclusivity: .chooseFirst)
  var flag1: Enum
}

let options = Options.parseOrExit()
print(options.flag1)
```
```
$ options -s -t
```
### Expected behavior
It should print "s" by itself, on a line

### Actual behavior
```
$ options -s -t
Error: Unknown option '-t'
Usage: options -s -t -u
```
