copy: It returns a shallow copy of a list.
### Feature Description
Add support for copy() method for lists in the Python translation.

### Test Code
This code should work when this issue is fixed:
```python
lst = [2, 3, 5]

new_lst = lst.copy()

print(new_lst)
>> [2, 3, 5]
```

### Proposed Solution
See description in https://github.com/pyccel/pyccel/issues/1529
