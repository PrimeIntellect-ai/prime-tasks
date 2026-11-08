[New Rule] Create dictionary directly
## Explanation

Do not use a line to create a dictionary, and then populate it. Do it directly. PyCharm has this check, which is rather neat; I think it's in Pylint as I think this linter is used behind the scenes when you run code inspection on a project. It's a bit faster (nanoseconds, whatever), and it reads nicer.

## Example

```python
# Bad
a = {}
a['b] = 'c'

# Good
a = {'b': 'c'}
```
