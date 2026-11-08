`Port` should validate that names are sanitary
### Describe the bug

When creating a `Port`, the expectation is that the name will not change.  Since `Port` extends from `Logic`, and `Logic` was updated to prevent names from being unsanitary by renaming them using the `Sanitizer`, it is now possible that the name will be sanitized silently, leading to bugs down the line.

Usually, it's not a good idea to name a port an unsanitary name ever, but sometimes it makes sense to want to name it something unsanitary if you know it will always be uniquified such that it will not actually be unsanitary on an interface.

### To Reproduce

Name a `Port` a SystemVerilog keyword (e.g. "end"), uniqufiy it so that it's a legal name on an interface, then attempt to access `port("end")`

### Expected behavior

When constructing a `Port`, it will immediately throw an exception if the name is not sanitary.

### Actual behavior

Port name is silently sanitized, making `port` calls unable to find the port.

### Additional: Dart SDK info

_No response_

### Additional: pubspec.yaml

_No response_

### Additional: Context

Exists/introduced in ROHD v0.4.1
