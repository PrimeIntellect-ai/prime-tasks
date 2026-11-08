Ignore invalid number value
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the issue has not already been raised


### Issue

Now, if number/integer value is invalid, it will be skipped. Is that expected behavior?

```js
const stringify1 = fastJson({ type: 'object', properties: { a: { type: 'number' }} })
const stringify2 = fastJson({ type: 'object', properties: { a: { type: 'number', nullable: true }} })

stringify1({ a: 'invalid' }) // {}
stringify2({ a: 'invalid' }) // {}
```

### Additional contract requirements

When a value cannot be converted to a number or an integer, serializing an object that contains that value must throw an error instead of silently omitting the property. Values that can be converted to a number or an integer (for example the string `"42"` or the boolean `true`) must still be coerced and serialized as numbers.
