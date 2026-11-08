IntoIterator on ArrayBase
Why is there no IntoIterator implementation for ArrayBase itself? I want to collect all elements into another data structure (or just map its type, but that's not available either), but all I can access are references of the elements, which is kind of bad. I could use mem::replace, but that requires me to create dummy values, which is bad for performance. So I'd like to just consume the whole thing and collect it into a new data structure instead.

### Additional contract requirements

A consuming iterator yields elements in the array's logical iteration order, including when the array has nonstandard strides or reversed axes. If the iterator is dropped before it is exhausted, every initialized element it still owns must be dropped exactly once, including elements in the allocation that are not reachable through the array view.
