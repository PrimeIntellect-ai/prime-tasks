sortQueryParameters encodes the query string
Is it supposed to be like this?

**sortQueryParameters: true**

```js
normalizeUrl('http://sindresorhus.com/?url=http://example.com', {
    sortQueryParameters: true
});
//=> 'http://sindresorhus.com/?url=http%3A%2F%2Fexample.com'
```

**sortQueryParameters: false**

```js
normalizeUrl('http://sindresorhus.com/?url=http://example.com', {
    sortQueryParameters: false
});
//=> 'http://sindresorhus.com/?url=http://example.com'
```

### Additional contract requirements

- The `sortQueryParameters: true` output shown above is the behavior being questioned, not the desired result. Enabling query-parameter sorting should control parameter order only; it must not percent-encode characters in query values such as `:` and `/` that would otherwise remain literal.
- When normalizing `http://sindresorhus.com/?foo=bar*|<>:"`, the result must be exactly `http://sindresorhus.com/?foo=bar*|%3C%3E:%22`.
- With `sortQueryParameters: true`, normalizing `http://sindresorhus.com/?z=https://example.com/a/b&a=first` produces `http://sindresorhus.com/?a=first&z=https://example.com/a/b`.
