Verify - dependent rules
The docs state that `validator.verify()` cannot use dependent rules without `v-validate`:

> Note that Target Dependant Rules won't work as they require a target field being tracked which cannot be done without using the v-validate directive.

However, I don't understand why this is so.

Surely as an independent function, the additional values / rules could be passed in?

```js
validator.verify(value, rule, values, rules)
```

In my case, I will have all these, so it should be simple to derive a response?

### Additional contract requirements

`validator.verify()` must be able to evaluate target-dependent rules without a tracked `v-validate` field when the caller supplies the target values. Supply those values either through an options object containing `values`, or through the positional target-data arguments proposed above.
