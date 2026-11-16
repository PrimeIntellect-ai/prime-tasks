Crash when having a dictionary property (ArgumentDecoder.swift:89: Fatal error)
Swift argument parser crashes when adding a dictionary property - see attached reproducer.

**ArgumentParser version:** `1.2.2` (reproduced with `main` too)
**Swift version:**  `swift-driver version: 1.62.15 Apple Swift version 5.7.1 (swiftlang-5.7.1.135.3 clang-1400.0.29.51)
Target: arm64-apple-macosx13.0
`
### Checklist
- [x] If possible, I've reproduced the issue using the `main` branch of this package
- [x] I've searched for [existing GitHub issues](https://github.com/apple/swift-argument-parser/issues)

### Steps to Reproduce
Unpack the attached reproducible project and run from command line with:
`swift run swift-argument-parser-reproducer --command run`

The complete code is simply:
```swift
import ArgumentParser

typealias BenchmarkIdentifier=Int

struct BenchmarkResult: Codable {
    var x:Int
}

@main
struct BenchmarkTool: AsyncParsableCommand {
    @Option(name: .long, help: "The command to perform")
    var command: String

    var benchmarkResults: [BenchmarkIdentifier: [BenchmarkResult]] = [:] // comment this out to not crash

    mutating func run() async throws {
    }
}
```

### Expected behavior
```
hassila@ice ~/G/swift-argument-parser-reproducer> swift run swift-argument-parser-reproducer --command run
Building for debugging...
[3/3] Linking swift-argument-parser-reproducer
Build complete! (0.39s)
USAGE: benchmark-tool --command <command>

OPTIONS:
  --command <command>     The command to perform
  -h, --help              Show help information.

hassila@ice ~/G/swift-argument-parser-reproducer>
```

### Actual behavior
```
hassila@ice ~/G/swift-argument-parser-reproducer> swift run swift-argument-parser-reproducer --command run
Building for debugging...
[47/47] Linking swift-argument-parser-reproducer
Build complete! (4.50s)
ArgumentParser/ArgumentDecoder.swift:89: Fatal error
fish: Job 1, 'swift run swift-argument-pars...' terminated by signal SIGTRAP (Trace or breakpoint trap)
```

[swift-argument-parser-reproducer.zip](https://github.com/apple/swift-argument-parser/files/10731814/swift-argument-parser-reproducer.zip)
