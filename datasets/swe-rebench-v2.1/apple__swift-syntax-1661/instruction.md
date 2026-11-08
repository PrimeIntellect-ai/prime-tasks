Statements that are separated by a newline inside a block comment are not accepted
### Issue Kind

Parse of Valid Source Failed

### Source Code

```swift
let a = 2/*
*/let b = 3
```


### Description

The source code should parse fine but it doesn’t because the newline inside the block comment is trailing trivia to `2` and thus not considered to determine whether the second `let` is on a new line.
