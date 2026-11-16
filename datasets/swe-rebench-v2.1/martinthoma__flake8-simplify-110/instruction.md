[SIM907] Use Optional[Type] instead of Union[Type, None]
## Explanation

Sometimes people tend to write ``Union[Type, None]`` instead of ``Optional[Type]``.

## Example

```python
# Bad
def foo(a: Union[int, None]) -> Union[int, None]:
  return a

# Good
def foo(a: Optional[int]) -> Optional[int]:
  return a
```

### Additional contract requirements

- The rule applies to both parameter annotations and return annotations.
- The diagnostic message is `SIM907 Use 'Optional[<type>]' instead of 'Union[<type>, None]'`,
  where `<type>` is the single non-`None` type argument of the `Union`.
- The diagnostic is reported at the line and column of the offending `Union[...]`
  subscript expression.
