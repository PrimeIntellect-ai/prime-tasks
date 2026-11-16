isdisjoint : Returns True if two sets have no elements in common.
### Feature Description

**Add support for isdisjoint() method for sets in the Python translation.**
`isdisjoint(other)` :   Returns True if the calling set and the specified other set have no common elements, otherwise returns False.

### Test Code

This Code Should Work

```python
set1 = {1, 2, 3}
set2 = {4, 5, 6}
disjoint = set1.isdisjoint(set2)
print(disjoint)
>>> True
```

### Proposed Solution
See description in #1531
