MultiDict does not handle None values
The following code will result in a `TypeError`:
```python
invalid_values = MultiDict([('a', 'x'), ('b', ''), ('d', None)])
print(invalid_values.get('a', type=int))  # None
print(invalid_values.get('b', type=int))  # None
print(invalid_values.get('c', type=int))  # None
print(invalid_values.get('d', type=int))  # TypeError
```
I think the expected behavior would be to return `None` as all other error cases do.

[HIDDEN]
https://github.com/pallets/werkzeug/blob/d3dd65a27388fbd39d146caacf2563639ba622f0/src/werkzeug/datastructures/structures.py#L81-L84

### Additional contract requirements

- When type conversion in `MultiDict.get` raises `TypeError`, return the supplied default instead of propagating the exception. If no default is supplied, return `None`.
