`key in btree` should ignore OverflowError
Currently, `key in btree` ignores TypeError, so this all works:
```pycon
>>> import BTrees
>>> bt = BTrees.family32.II.BTree()
>>> 'abc' in bt
False
>>> bt.get('abc') is None
True
```

But if the key is outside the range allowed, it fails:
```pycon
>>> x = 2 ** 64
>>> x in bt
OverflowError: Python int too large to convert to C long
>>>  bt.get(x)
OverflowError: Python int too large to convert to C long
```

For consistency, the `OverflowError` should be ignored in those cases too. (This would happen automatically if it was a `TypeError` instead of an `OverflowError`.) The pure-Python implementation already handles this (…by raising a TypeError, I think).

Also weird and should not raise (works in pure-Python):
```pycon
>>> bt.has_key(1)
0
>>> bt.has_key('abc')
KeyError: 'abc'
>>> bt.has_key(x)
OverflowError: Python int too large to convert to C long
```

Confirmed this to be an issue back to 4.6. [The changes in 4.3.2](https://btrees.readthedocs.io/en/latest/changes.html#id9) were not sufficient for the overflow case.

### Additional contract requirements

Assigning an out-of-range key or value to a mapping (``t[key] = value``) must raise
``TypeError`` rather than ``OverflowError``, consistent with the conversion functions
``to_int`` and ``to_long``.
