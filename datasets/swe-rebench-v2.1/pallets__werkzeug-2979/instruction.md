dict datastructures could include `|` and `|=` behavior
Python 3.9 added two operators to dict:

* `a | b` does `{*a, *b}`
* `a |= b` does `a.update(b)`

Implement this for our various dict datastructures (assuming it makes sense in each case).

### Additional contract requirements

For a dict-like data structure that supports binary union, `a | b` returns a new merged result and leaves `a` unchanged. Entries from `b` are applied using the structure's ordinary update semantics, including when both operands contain the same key. For a single-valued mapping, the value from `b` replaces the existing value; for a multi-valued mapping, the result follows that structure's usual handling of repeated keys.
