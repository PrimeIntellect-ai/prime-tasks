[Adjust Rule] SIM110
## Desired change

* **Rule(s)**: SIM110
* **Adjustment**: Fix issue

## Example

This is an example where the mentioned rule(s) would currently be suboptimal:

```python
#  Code
for el in [1,2,3]:
    if is_true(el):
        return True
raise Exception

# Current message
SIM110 Use 'return any(is_true(el) for el in [1, 2, 3])'

# Desired message: Either none or the following:
SIM110 Use 'if any(is_true(el) for el in [1, 2, 3]): return True; raise Exception'
```
