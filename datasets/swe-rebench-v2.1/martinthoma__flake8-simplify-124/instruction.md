[Adjust Rule] SIM111 - Detect if another statement comes after the loop
## Desired change

* **Rule(s)**: SIM111
* **Adjustment**: Detect if another statement comes after the loop

## Explanation

The below code is flagged with SIM111, but if I would would use the suggested code, the `call_method` call would be lost.

## Example

```python
for a in my_list:
  if a == 2:
    return False
call_method()
return True
```
