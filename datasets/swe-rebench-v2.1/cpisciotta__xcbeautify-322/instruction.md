[New Output] Support SwiftDriver Compilation Requirements Output
### What's the uncaptured output?

```
SwiftDriver\ Compilation\ Requirements SomeTarget normal arm64 com.apple.xcode.tools.swift.compiler (in target 'Target' from project 'Project')
    cd /path/to/some/package
    builtin-Swift-Compilation-Requirements -- /Applications/Xcode-15.0.1.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc ...
```

### Suggested Regex

_No response_

### Suggested Output

_No response_

### Additional Context

_No response_

### Additional contract requirements

- Formatting a SwiftDriver Compilation Requirements line must return nil (produce no formatted output).
