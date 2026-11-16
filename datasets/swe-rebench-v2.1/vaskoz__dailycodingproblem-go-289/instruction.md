Day 139
Good morning! Here's your coding interview problem for today.

This problem was asked by Google.

Given an iterator with methods next() and hasNext(), create a wrapper iterator, PeekableInterface, which also implements peek(). peek shows the next element that would be returned on next().

Here is the interface:
```
class PeekableInterface(object):
    def __init__(self, iterator):
        pass

    def peek(self):
        pass

    def next(self):
        pass

    def hasNext(self):
        pass
```

### Additional contract requirements

- In Go, the wrapper is the type `PeekableIterator` in package `day139`. It wraps any value that has the methods `Next() interface{}` and `HasNext() bool`. The wrapped value is supplied through the exported field `Iter`, so a wrapper is built as `PeekableIterator{Iter: it}`.
- `Peek()` returns the element that the next `Next()` call would return, without consuming it. Calling `Peek()` repeatedly returns the same element.
- `Next()` returns the element that `Peek()` showed when one was shown, and advances past it. The call after that returns the element following it.
- `HasNext()` reports true while `Next()` would still yield an element, including when that element has only been shown by `Peek()`.
- Iterating with `Next()` and `HasNext()` without calling `Peek()` returns every element of the wrapped iterator in order.
