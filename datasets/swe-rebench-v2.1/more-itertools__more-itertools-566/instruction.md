New recipe: before_and_after
This issue is to add the new `before_and_after` function from the 3.10 [itertools docs](https://github.com/python/cpython/blame/3.10/Doc/library/itertools.rst#L858).

Needed:
* The implementation from the recipe
* Type stub
* Tests

### Additional contract requirements

`before_and_after(predicate, it)` accepts an iterable and returns two iterators. The first yields the initial consecutive elements for which the predicate is true; the second yields the remaining elements beginning with the first element for which the predicate is false.
