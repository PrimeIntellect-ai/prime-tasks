Add flatMapIndexed
https://kotlinlang.org/api/latest/jvm/stdlib/kotlin.collections/flat-map-indexed.html

### Additional contract requirements

Add a public method `flatMapIndexed<R>(KtIterable<R> Function(int index, T) transform)` on the `KtIterableExtensions<T>` extension on `KtIterable<T>` (in `lib/src/collection/kt_iterable.dart`). It returns a `KtList<R>` containing all elements produced by `transform`, in order, passing each element's zero-based index and the element itself.

Add a public method `flatMapIndexedTo<R, C extends KtMutableCollection<R>>(C destination, KtIterable<R> Function(int index, T) transform)` on the same extension. It appends all elements produced by `transform` to `destination`, in order, passing each element's zero-based index and the element itself, and returns the same `destination`.

The existing `flatMapTo<R, C extends KtMutableCollection<R>>(C destination, KtIterable<R> Function(T) transform)` method appends all elements produced by `transform` to `destination`, in order, and returns the same `destination`.
