Preprocessor flag can't be retriever when protocol has more then one attribute
**Bug Description:**

When multiple attributes are attached to a protocol, such as `Spyable` and `MainActor`, there is an issue in retrieving `behindPreprocessorFlag` value.

Consider the following declaration:
```swift
@Spyable(behindPreprocessorFlag: "DEBUG")
protocol Foo {}
```
In this scenario, we can successfully retrieve the value of `behindPreprocessorFlag` because `Spyable` is the only attribute. However, if we add an additional attribute as shown below:
```diff
+@MainActor
@Spyable(behindPreprocessorFlag: "DEBUG")
protocol Foo {}
```
The retrieval of the `Spyable` attribute's value becomes problematic. The current implementation only considers the first attribute attached to the protocol declaration. Therefore, when `Spyable` is not the first attribute, its values become inaccessible.

**Proposed Solution:**

To resolve this issue, the approach to attribute retrieval needs modification. [HIDDEN]

### Additional contract requirements

- When a protocol has multiple attributes, a `@Spyable(behindPreprocessorFlag: "…")` attribute must be honored regardless of its position, and the generated spy must be guarded by the specified flag.
