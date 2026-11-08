/// // comments
```dart
  /// // BN_free frees the data referenced by |bn| and, if |bn| was originally
  /// // allocated on the heap, frees |bn| also.
  void BN_free(
    ffi.Pointer<BIGNUM> bn,
  ) {
    return _BN_free(
      bn,
    );
  }
```

The comments copying includes the `//`'s which were already in the C source. Would it be possible to detect and remove these?

### Additional contract requirements

When C full comments contain repeated leading `//` comment markers, generated Dart documentation must omit those redundant markers while preserving the comment text.
