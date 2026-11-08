[New Output] Support SwiftDriver Target Output
### What's the uncaptured output?

```
SwiftDriver SomeTargetName normal x86_64 com.apple.xcode.tools.swift.compiler (in target 'Target' from project 'Project')
    cd /path/to/DerivedData/SourcePackages/checkouts/SwiftPackage
    builtin-SwiftDriver -- /Applications/Xcode-15.0.1.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -module-name SomeTargetName ...
```

### Suggested Regex

_No response_

### Suggested Output

_No response_

### Additional Context

_No response_

### Additional contract requirements

Recognize SwiftDriver target output of the demonstrated form as handled output rather than leaving it uncaptured.
