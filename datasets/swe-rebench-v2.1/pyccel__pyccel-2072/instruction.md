intersection : Returns a new set with elements that are common to all sets.
### Feature Description

**Add support for intersection() method for sets in the Python translation.**
`intersection(*others)` : Returns a new set containing elements that are present in all sets, the intersection of all sets.

### Test Code

This Code Should Work

```python
set1 = {1, 2, 3}
set2 = {2, 3, 4}
intersect_set = set1.intersection(set2)
print(intersect_set)
>>> {2, 3}
```

### Proposed Solution
See description in #1531
