pop: removes and returns the last value from the list or the given index value.
### Feature Description
Add support for pop() method for lists in the Python translation.

### Test Code
This code should work when this issue is fixed:
```python
>> a = [1, 3]
>> b = a.pop(3)
>> print(b)
>> 3
```

### Proposed Solution
See description in https://github.com/pyccel/pyccel/issues/1529

### Additional contract requirements

- When an index is supplied, `pop` removes and returns the element at that zero-based index. Negative indices count from the end of the list. An index outside the valid range raises `IndexError`. In the example, index `3` is out of range for `[1, 3]`; to pop and return `3`, use index `1`.
- Provide a public class `ListPop` in the module `pyccel.ast.builtin_methods.list_methods`. Its constructor is `ListPop(list_variable, index_element=None)`, where `list_variable` is the list being popped from and `index_element` is the optional index of the element to remove.
- A `ListPop` instance exposes the read-only properties `pop_index` (the index element passed to the constructor, or `None` when no index was given) and `list_variable` (the list variable passed to the constructor).
- The `dtype` and `precision` of a `ListPop` instance match the element type of the list it operates on.
