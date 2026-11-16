[Adjust Rule] SIM102: 'if __name__ == "__main__"' does not count
## Desired change

* **Rule(s)**: SIM102
* **Adjustment**: Ignore `if __name__ == "__main__"`

## Explanation

the check `if __name__ == "__main__"` is special. People recognize it as a special part of a script. Although one can combine things, I think it's better not to do it.

## Example

The following should not trigger SIM102

```python
if __name__ == "__main__":
    if foo(): ...
```
