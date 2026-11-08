Parser crash with skipSingle and string literals
### Issue Kind

Parser Crash

### Source Code

```swift
if p{""
```


### Description

_No response_

### Additional contract requirements

Parsing the source `if p{""` must not crash and must produce exactly one
diagnostic, whose message is `expected '}' to end 'if' statement`.


- The diagnostic must be located at the end of the input.
