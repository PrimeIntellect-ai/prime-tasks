useFuture/useStream: does initialData need to be required?
At 0.16.0 with nullsafety useFuture gets `required T initialData` parameter:
https://github.com/rrousselGit/flutter_hooks/blob/2b02b99ce6b327fd3a6df6f9c52cb2fe791600f6/lib/src/async.dart#L11-L15

This means when there is no initial data, one have to explicitly pass null:
```dart
final snapshot = useFuture(future, initialData: null);
```

Are there any benefits of making it required?

### Additional contract requirements

- `useFuture` and `useStream` can be called without an `initialData` argument. When it is omitted, the returned snapshot has no data (`data` is `null`) until the future or stream produces a value or an error.
- When `initialData` is passed, the snapshot starts with that value, as it does today.
