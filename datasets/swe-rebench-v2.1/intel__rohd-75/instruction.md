Add support to do `swizzle`-like operations on `LogicValues`
## Motivation
The `swizzle` and `rswizzle` operations on `Logic` are useful, but there's no equivalent for `LogicValues`.  It would be nice to have similar functionality available for `LogicValues`.

## Desired solution
Perhaps some sort of `Swizzleable` type or something so that `swizzle` and `rswizzle` can directly be reused as parameterized functions instead of reimplementing again?  For example:
```dart
SwizzleableType swizzle<SwizzleableType extends Swizzleable>(List<SwizzleableType> components) => ...
```

## Alternatives considered
Available current solution is just doing things like a bitwise OR, but that's less convenient.  A specific function or constructor for `LogicValues` could work too.

### Additional contract requirements

- Calling `swizzle()` on a `List<LogicValues>` must return one `LogicValues` that concatenates the list elements, with the first element in the most-significant bits. Each element's bits (including mixed widths and `x`/`z` values) must appear unchanged in the result.
- Calling `rswizzle()` on a `List<LogicValues>` must return one `LogicValues` that concatenates the list elements, with the first element in the least-significant bits. Each element's bits must appear unchanged in the result.
