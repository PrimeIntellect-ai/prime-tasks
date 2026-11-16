Long import statements cause diktat to fail
## Describe the bug

Import statements that are longer than the configured maximum line length are considered an error by diktat.

## Expected behavior

Not entirely sure. The problem is that the imports can't be targeted by `@Suppress` annotations, so the only recurse is `file:Suppress`ing the error for the whole file or using workarounds that do not help code legibility in any way, but rather hinder it (e.g. putting `typealias`es in files with shorter package names).

I suppose ignoring import statements, or adding an option for such behavior, might be a solution. Alternatively, disabling checks via comments could be an alternative.

## Observed behavior

Diktat raises an error for each line containing an import statement that is longer than the configured limit.

## Steps to Reproduce

All that is needed is a file that conforms to all diktat rules, and then adding an import statement that is too long to it.

## Environment information

* diktat version: 1.0.0-rc.3
* build tool (maven/gradle): Gradle
* how is diktat run (CLI, plugin, etc.): IntelliJ IDEA, CLI (both Gradle diktatCheck tasks).
* kotlin version: 1.5.30
* operating system: macOS, Linux

### Additional contract requirements

- Import statements that exceed the configured maximum line length must not produce line-length errors. This exception must be limited to import statements; over-limit non-import lines must remain subject to the line-length check, without requiring suppression of the entire file.
