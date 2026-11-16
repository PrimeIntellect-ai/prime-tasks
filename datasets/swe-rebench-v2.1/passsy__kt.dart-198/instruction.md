KMutableIterator.remove() doesn't remove item from collection
```dart
var abc = mutableListOf(["a", "b", "c"]);
final KMutableIterator<String> i = abc.iterator();
assert(i.next() == "a");
i.remove();
assert(abc[0] == "b"); // Failed assertion: 'abc[0] == "b"': is not true.
```

`abc[0]` is still `"a"` because remove doesn't remove the item from the actual collection. Instead, it gets removed from the internal copy inside the iterator.

To fix this problem a big refactoring is required so that remove actually removed the item from the original collection.

This is how kotlin [solves this](https://github.com/JetBrains/kotlin/blob/ba6da7c40a6cc502508faf6e04fa105b96bc7777/libraries/stdlib/js/src/kotlin/collections/InternalHashCodeMap.kt)
