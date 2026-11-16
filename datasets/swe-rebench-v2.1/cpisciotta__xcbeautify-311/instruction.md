[New Output] Support Note Output
### What's the uncaptured output?

```
note: Building targets in dependency order
```
```
note: Metadata extraction skipped. No AppIntents.framework dependency found. (in target 'Target' from project 'Project')
```
```
note: Run script build phase 'SomeRunScriptBuildPhase' will be run during every build because the option to run the script phase "Based on dependency analysis" is unchecked. (in target 'Target' from project 'Project')
```
```
note: Target dependency graph (12 targets)
```

### Suggested Regex

_No response_

### Suggested Output

_No response_

### Additional Context

_No response_

### Additional contract requirements

Recognize Xcode log lines beginning with `note:` as note output and emit their note information rather than leaving them uncaptured.
