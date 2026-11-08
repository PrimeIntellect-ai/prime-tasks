Expose ParserError exception to top level imports
Currently if you want to catch the `ParserError` when calling `pendulum.parse('string')`, you have to catch it with:

```
try:
  pendulum.parse('string')
except pendulum.parsing.exceptions.ParserError:
  pass
```

unless you've explicitly imported that part of the module in. There is already a `pendulum.exceptions`, so is there any reason why the `ParserError` couldn't be put into that same module or imported into the base init? I can make the PR for it, I just wanted to get clarity around whether this was by design or if it was something that wasn't a use case. I don't want to catch `ValueError`, mostly because that's not the exception being thrown.
