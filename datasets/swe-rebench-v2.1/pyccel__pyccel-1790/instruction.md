remove: method removes the first occurrence of the element with the specified value.
### Feature Description
Add support for remove() method for lists in the Python translation.

### Test Code
This code should work when this issue is fixed:
```python

lis = [1, 2, 3]
lis.remove(2)
print(lis)
>> [1, 3]
```

### Proposed Solution
See description in https://github.com/pyccel/pyccel/issues/1529

### Additional contract requirements

- `list.remove` removes the first occurrence of the element with the specified value and mutates the list in place.
- The element passed to `list.remove` must have the same type as the list's element type and a rank one less than the list's rank. When it does not, compiling the program with `epyccel` fails with a `pyccel.errors.errors.PyccelSemanticError`.
- `list.remove` returns no value (Void). Using its result (for example assigning it to a variable) is a semantic error reported as a `PyccelSemanticError`.
