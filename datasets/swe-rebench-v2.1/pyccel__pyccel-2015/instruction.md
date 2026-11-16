union : Returns a new set with elements from the set and all others.
### Feature Description

**Add support for union() method for sets in the Python translation.**
`union(*others)` :  Returns a new set containing all unique elements present in the calling set as well as all specified other sets.

### Test Code

This Code Should Work

```python
set1 = {1, 2}
set2 = {3, 4}
union_set = set1.union(set2)
print(union_set)
>>> {1, 2, 3, 4}
```

### Proposed Solution
See description in #1531
