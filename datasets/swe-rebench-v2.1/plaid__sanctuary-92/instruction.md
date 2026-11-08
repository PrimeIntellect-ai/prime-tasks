[HIDDEN]
Current behaviour:

```javascript
> S.or(true, true, true)
TypeError: Expecting a function in instanceof check, but got undefined
```

Desired behaviour:

```javascript
> S.or(true, true, true)
TypeError: ‘or’ requires two arguments; received three arguments
```

`S.or(true)(true, true)` should behave the same way.

### Additional contract requirements

- Sanctuary functions must throw a `TypeError` when called with more arguments than their declared arity. This applies both to direct calls and to calls of functions returned by partial application.
