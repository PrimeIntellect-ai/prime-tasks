[New Output] Support MkDir Output
### What's the uncaptured output?

```
MkDir /path/to/bundle.bundle (in target 'Target' from project 'Project')
    cd /path/to/swift/package
    /bin/mkdir -p /path/to/bundle.bundle
```

### Suggested Regex

_No response_

### Suggested Output

_No response_

### Additional Context

_No response_

### Additional contract requirements

- Lines that begin with `MkDir` (matching the pattern `^MkDir.*`) must be recognized as captured output, so that they are no longer reported as uncaptured.
