[BUG] shouldPreserveState may wrongfully preserve state when it shouldn't
Was looking into the library's code to see how the hook keys are being compared, when I noticed what I think to be a potential bug?

The (unmodified) library code in question is:
```dart
static bool shouldPreserveState(Hook<Object?> hook1, Hook<Object?> hook2) {
    final p1 = hook1.keys;
    final p2 = hook2.keys;

    if (p1 == p2) {
      return true;
    }
    // if one list is null and the other one isn't, or if they have different sizes
    if (p1 == null || p2 == null || p1.length != p2.length) {
      return false;
    }

    final i1 = p1.iterator;
    final i2 = p2.iterator;
    // ignore: literal_only_boolean_expressions, returns will abort the loop
    while (true) {
      if (!i1.moveNext() || !i2.moveNext()) {
        return true;
      }

      final curr1 = i1.current;
      final curr2 = i2.current;

      if (curr1 is num && curr2 is num) {
        // Checks if both are NaN
        if (curr1.isNaN && curr2.isNaN) {
          return true;
        }

        // Checks if one is 0.0 and the other is -0.0
        if (curr1 == 0 && curr2 == 0) {
          return curr1.isNegative == curr2.isNegative;
        }
      }

      if (curr1 != curr2) {
        return false;
      }
    }
  }
  ```

## The problematic snippets

[HIDDEN]

```dart
// Checks if both are NaN
        if (curr1.isNaN && curr2.isNaN) {
          return true;
        }
```
and
```dart
// Checks if one is 0.0 and the other is -0.0
        if (curr1 == 0 && curr2 == 0) {
          return curr1.isNegative == curr2.isNegative;
        }
```

## The solution?
```dart
// Checks if both are NaN
        [HIDDEN]
```
and
```dart
// Checks if one is 0.0 and the other is -0.0
        [HIDDEN]
```

P.s. Hopefully I'm not missing something in my analysis

### Additional contract requirements

- A pair of NaN keys, or a pair of zero keys with the same sign, counts as a match for those corresponding keys but must not by itself determine whether state is preserved. The remaining keys must still be compared; if any later key differs, state must not be preserved.
- Zero keys with different signs do not match.
