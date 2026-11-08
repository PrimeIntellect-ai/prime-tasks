Error handling fails in presence of incremental MH transforms
For example:

```js
Infer({
  method: 'incrementalMH',
  model() {
    assert.ok(false, 'fail');
  }});
```

Fails with:

```
TypeError: Cannot read property 'line' of undefined
```

... rather than showing:

```
AssertionError: fail
    at err.wppl:49

48|   model() {
49|     assert.ok(false, 'fail');
    -----------^
50|   },
```

I understand the problem and will submit a fix soon.

(Thanks @mhtess for pointing this out to me.)

### Additional contract requirements

- For an `incrementalMH` model containing `assert.ok(false)`, the debug stack trace must include a frame with `name: 'ok'`, `line: 3`, and `col: 9`.
