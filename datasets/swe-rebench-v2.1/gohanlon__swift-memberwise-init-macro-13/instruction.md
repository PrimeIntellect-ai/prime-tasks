Add `@Init(assignee:type:)` to (awkwardly) support property wrappers
MemberwiseInit can be made to support property wrappers like SwiftUI's `@Binding` with the addition of two new arguments:

```swift
import SwiftUI

@MemberwiseInit
struct CounterView: View {
  @Init(assignee: "self._count", type: Binding<Int>)
  @Binding var count: Int
}
```

With that, MemberwiseInit can provide the expected initializer for a `@Binding`-wrapped property:

```swift
internal init(
  property: Binding<Int>
) {
  self._count = count
}
```

This expressiveness may also support the use of other framework-vended property wrappers, custom property wrappers and macros.

### Additional contract requirements

For the illustrated `count` property, the generated initializer parameter is named `count` (so callers use the `count:` argument label), and its value is assigned to the `self._count` backing storage. The word `property` in the displayed initializer signature is not the required argument label.
