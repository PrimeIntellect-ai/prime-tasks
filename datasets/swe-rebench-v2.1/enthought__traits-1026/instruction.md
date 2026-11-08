TraitListObject does not notify if an operation keeps the list unchanged.
The `TraitListObject` does not notify if an operation such as `__setitem__` does not change the underlying list. i.e. For example, if you have a list `lst=[1,2,3]`, then setting `lst[0] = 1` does not fire an event.

Is this desirable ?
Does it make more sense to not have this smartness builtin ?

The comparison of added and removed values is done with `__eq__` and may sometimes fail.

### Additional contract requirements

- Replacing list items with values equal to the current ones still sends a list change notification. For a list `[1, 2, 3]`, `lst[0] = 1` sends a notification with index 0, removed `[1]` and added `[1]`. Likewise, `lst[0:2] = [1, 2]` sends a notification with removed `[1, 2]` and added `[1, 2]`.
- A list operation sends a notification only when it adds or removes at least one item. For example, `lst[3:] = []` on a three-element list sends no notification.
- Whether a notification is sent for an item replacement must not depend on the old and new items comparing equal. Replacing an item whose `__eq__` raises an exception still sends a notification carrying the removed and added items, and the replacement does not raise.
