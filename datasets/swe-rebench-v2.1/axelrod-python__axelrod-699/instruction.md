Strategy Filtering by Dictionary
Within the api, there are a set of functions to filter strategies from their classifier entries using a dictionary. (This is because parameters within a url are passed as dictionary).

For example, the url https://axelrod-api.herokuapp.com/strategies/?stochastic=false&inspects_source=true passes the following dictionary:
```
{
    'stochastic': 'false',
    'inspects_source': 'true'
}
```
and it's then used to generate the list of strategies which satisfy those filtering criteria.

We could implement that functionality within the library itself, so that we could do something like:
```
filter = {
    'stochastic': 'false',
    'inspects_source': 'true'
}
print(axelrod.filtered_strategies(filter))
```

This wouldn't add anything that couldn't already be done with a list comprehension. The same filtering can be done already with:
```
print([[s in axl.strategies if not s.classifier[’stochastic’] and s.classifier[‘inspects_source']]))
```

However, it would add an extra capability to the library rather than it existing only within the api.

### Additional contract requirements

- The values in a `filterset` are compared directly against the corresponding
  entries of each strategy's `classifier` dictionary. They are expected to be
  the native Python types stored in classifier dictionaries (`bool`, `int`,
  `float`, or `list`); string values such as `'true'` or `'false'` are not
  converted to booleans.
- When a filter dictionary supplies multiple criteria, a strategy is included
  only if it satisfies every supplied criterion.
