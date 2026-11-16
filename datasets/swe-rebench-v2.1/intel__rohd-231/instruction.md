Make `endIndex` in `getRange` an optional positional argument, default to width
### Motivation

It's relatively common to want to grab a bus or value from a certain bit all the way to the end, but right now that requires explicitly specifying the width as the `end` argument of `getRange`.  It would be nice if supplying only the `start` would default to grabbing all the way to the end.

### Desired solution

Modify `getRange` in both `Logic` and `LogicValue` so that `endIndex` is an optional positional argument:
```dart
[HIDDEN]
```
If `endIndex` is null, then default the value of it to `width`.

### Alternatives considered

_No response_

### Additional details

_No response_

### Additional contract requirements

- Both `Logic.getRange` and `LogicValue.getRange` must accept `endIndex` as an optional positional argument. If it is omitted or null, the range extends to the instance’s width.
