Add remaing Flow methods
Add folowing flow methods
Sample
Debounce
DebounceBy
Collect
Scan
Zip
zipAll
zipWithIndex

### Additional contract requirements

- `sample(n)` emits every nth source element, in source order. No behavior is required for a non-positive interval.
- `debounce()` suppresses a source element when it equals the immediately preceding element; other elements remain in source order. `debounceBy(f)` applies the same rule to the keys returned by `f`, while emitting the original elements.
- `collect(f)` applies a mapping that returns an optional value to each source element, emits values that are present, and skips empty results.
- `scan(initial, f)` emits the initial accumulator first, then emits the updated accumulator after each source element.
- `zip(other)` pairs elements in source order by matching position and ends when either input has no more elements. `zipAll(other, thisDefault, otherDefault)` pairs by matching position and supplies the appropriate default for elements from the longer input after the shorter input ends. `zipWithIndex()` associates each source element with its zero-based position. These operations expose each pair's two component values; no particular pair representation is required.
