Variable declaration of forced unwrapped optional fails
```swift
@Spyable protocol Name {
  var name: String!
}
```

**Error Message**
```
macro expansion @Spyable:30:29: error: using '!' is not allowed here; perhaps '?' was intended?
`- /Users/matejko/Developer/swift-spyable/Examples/Sources/ViewModel.swift:19:2: note: expanded code originates here
17 |   func append(name: (any Codable) -> (any Codable)?)
18 | //  func get() -> any Codable
19 | }
   +--- macro expansion @Spyable ---------------------------------------
   | 28 |         }
   | 29 |     }
   | 30 |     var underlyingAddress: (String!)!
   |    |                             `- error: using '!' is not allowed here; perhaps '?' was intended?
   | 31 |     var added: () -> Void {
   | 32 |         get {
   +--------------------------------------------------------------------
20 |
21 | final class ViewModel {
```
