`TypeError` in Fortran printer when creating `range` from `max`
### Describe the bug
The Fortran printer raises an internal `TypeError` when a `range` is created from an expression that contains `max`.

### To Reproduce
Provide code to reproduce the behavior:
```python
def sum_max_range(a : int, b : int) -> int:
    k = 0
    c = max(a, b)
    for i in range(c):
        k += i
    return k


if __name__ == "__main__":
    k = sum_max_range(0, 0); print(k); assert k == 0
    k = sum_max_range(2, 2); print(k); assert k == 1
    k = sum_max_range(0, 4); print(k); assert k == 6
    k = sum_max_range(2, 5); print(k); assert k == 10
    k = sum_max_range(3, 1); print(k); assert k == 3
```

### Language
Fortran

### Additional context
This code works with the C backend.
