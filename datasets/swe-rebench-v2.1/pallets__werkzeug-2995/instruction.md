MultiDict converts byte values to int list since version 3.1.0
Since version 3.1.0, when I create a MultiDict with a bytes value as input it stores the bytes value in the MultiDict as a list of integer values. Prior to 3.1.0, this would preserve the bytes value in the MultiDict.

To reproduce, run this snippet with werkzeug installed:
```python
from werkzeug.datastructures import MultiDict

multi_dict = MultiDict({
    'bytes_value': b'abc',
    'str_value': 'abc'
})

print(multi_dict)
```

Running the above on version 3.1.0 prints:
`MultiDict([('bytes_value', 97), ('bytes_value', 98), ('bytes_value', 99), ('str_value', 'abc')])`

Running the snippet with version 3.0.6 prints:
`MultiDict([('bytes_value', b'abc'), ('str_value', 'abc')])`

I expected the behaviour from 3.0.6 to be preserved in this case

Environment:
- Python version: 3.11
- Werkzeug version: >= 3.1.0

### Additional contract requirements

- `werkzeug.datastructures.iter_multi_items(mapping)` is a public function. It
  accepts a `MultiDict`, a `Mapping`, or an iterable of `(key, value)` tuples,
  and returns an iterator of `(key, value)` tuples. When a mapping value is a
  `list`, `tuple`, or `set`, it yields one `(key, element)` pair per element;
  any other value, including `str` and `bytes`, is yielded as a single
  `(key, value)` pair.
- When constructing a `MultiDict` from a mapping, a `list`, `tuple`, or `set`
  value is expanded into multiple values, while any other value, including
  `str` and `bytes`, is stored as a single value.
