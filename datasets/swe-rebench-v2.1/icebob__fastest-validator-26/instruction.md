Multiple validators + optional = false negative
```js
> (new (require('fastest-validator'))).validate({}, {
    a: [
        { type: 'number', optional: true },
        { type: 'string', optional: true },
    ]
})
[ { type: 'required',
    expected: undefined,
    actual: undefined,
    field: 'a',
    message: 'The \'a\' field is required!' } ]
```

I expected `a` not to be considered required.
