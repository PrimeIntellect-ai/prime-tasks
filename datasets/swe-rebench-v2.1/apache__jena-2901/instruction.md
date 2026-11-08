LATERAL: Unexpectedly unbound variable.
### Version

5.3.0-SNAPSHOT

### What happened?

I am not sure whether this is according to [SEP7](https://github.com/w3c/sparql-dev/blob/main/SEP/SEP-0007/sep-0007.md) or a bug in Jena:

I am trying to inject a value using lateral into a BIND in a subquery. The following works:
```sparql
SELECT * {
  BIND('x' AS ?xIn)
  LATERAL {
    { SELECT ?xIn ?xOut { BIND(?xIn AS ?xOut) } } # The algebraic no-op SELECT * gives the same result.
  }
}
```
The result is:

| ?xIn | ?xOut |
|------|-------|
| x    | x     |


However, if in the lateral block there is a Join, then it breaks:
```sparql
SELECT * {
  BIND('x' AS ?xIn)
  LATERAL {
    BIND("foo" AS ?foo)
    { SELECT ?xIn ?xOut { BIND(?xIn AS ?xOut) } } # SELECT * gives the same result.
  }
}
```

In the result, `?xOut` is (for me) unexpectedly unbound.
| ?xIn | ?foo | ?xOut |
|------|------|-------|
| x    | foo  |       |

I think this is a bug in Jena (but perhaps I am misunderstanding something about the scoping rules).

### Relevant output and stacktrace

_No response_

### Are you interested in making a pull request?

Maybe
