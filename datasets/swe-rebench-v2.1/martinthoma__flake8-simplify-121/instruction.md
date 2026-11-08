[SIM909] Avoid reflexive assignment
## Explanation

Assigning a name to itself is a no-op and should be eliminated.

## Example

```python
# Bad
foo = foo

# Good
# (nothing)

# Bad
foo = foo = 42

# Good
foo = 42
```

### Additional contract requirements

- Report each violation as `<line>:<column> SIM909 Remove reflexive assignment '<assignment source>'`, using the assignment’s source text in the message.
