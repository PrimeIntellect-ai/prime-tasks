[New Rule] Use comparision directly instead of bool(comparison)
## Explanation

Comparisons return boolean values. No need to wrap it in a bool-call

## Example

```python
# Bad
bool(a == b)

# Good
a == b
```

### Additional contract requirements

- For `bool(a == b)` on line 1, report `1:0 SIM901 Use 'a == b' instead of 'bool(a == b)'`.
