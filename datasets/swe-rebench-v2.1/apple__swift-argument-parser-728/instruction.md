Confusing error output when passing a single-dash unknown option that contains some valid short label option names
<!--
    Thanks for contributing to the Swift Argument Parser!

    Before you submit your issue, please replace each paragraph
    below with the relevant details for your bug, and complete
    the steps in the checklist by placing an 'x' in each box:

    - [x] I've completed this task
    - [ ] This task isn't completed
-->

see relevant discussion on the swift forums here: https://forums.swift.org/t/why-does-swift-treat-double-dash-command-line-arguments-differently/77727/8

**ArgumentParser version:**
`main` branch (commit: a01856b)
**Swift version:**
swift-driver version: 1.115 Apple Swift version 6.0.2 (swiftlang-6.0.2.1.2 clang-1600.0.26.4)
Target: arm64-apple-macosx14.0

### Checklist
- [x] If possible, I've reproduced the issue using the `main` branch of this package
- [x] I've searched for [existing GitHub issues](https://github.com/apple/swift-argument-parser/issues)
  - found https://github.com/apple/swift-argument-parser/issues/23 which seems a bit similar in the high level description, but the details seem probably different

### Steps to Reproduce

run this test case in `ParsableArgumentsValidationTests`:

```swift
extension ParsableArgumentsValidationTests {
    func test_shouldMaybeProduceUnknownOptionErrorInsteadOfMissingValue() throws {
      struct SomeArgs: ParsableArguments {
        @Option(name: .shortAndLong)
        var x_arg: Int

        @Option(name: .shortAndLong)
        var z_arg: Int
      }

      // swap order of 'x' and 'z' in the string to get different error output
      AssertErrorMessage(
        SomeArgs.self,
        [
          "-should_maybe_be_an_unknown_option_error_but_is_a_missing_value_error_when_it_includes_x_or_z",
        ],
        "Unknown option '-should_maybe_be_an_unknown_option_error_but_is_a_missing_value_error_when_it_includes_x_or_z'"
      )
      // actually: "Missing value for '-x <x_arg>'"
    }
}
```

### Expected behavior
an error indicating the given option is unrecognized

### Actual behavior
an error is produced suggesting that the option name is valid but is missing a value

### Additional contract requirements

- For the input `-long_option_with_x_or_z`, the error message must be exactly:

```text
Unknown option '-long_option_with_x_or_z'
   or: Missing value for '-x <x-arg>' in '-long_option_with_x_or_z'
```

For the input `-long-with-x-or-z`, the error message must be exactly:

```text
Unknown option '-long-with-x-or-z'. Did you mean '-long-with-x-or-y'?
   or: Missing value for '-x <x-arg>' in '-long-with-x-or-z'
```
