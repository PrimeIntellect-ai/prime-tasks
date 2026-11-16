Possible bug: Optional enum string fails validation on empty input
## Description

I do not know if this behaviour is by design or not but when I declare some prop like this one:

```javascript
const schema = {
      Status: {
        type: 'string',
        uppercase: true,
        enum: ['a', 'b', 'c'],
        optional: true,
        nullable: true
      }
}
validate({Status: ''}, schema)
```

the validation process fails inferring that the empty value `''` is not in the `stringEnum`, even if I've specified the `optional` and the `nullable` features. Is this by design? Or shouldn't be the null and empty string, in this case, considered as part of the enumeration or checked before validating the enum? If so it should be documented or at least using `optional` or `nullable` with `enum` should throw an exception...

### Additional contract requirements

- A string field definition in a schema supports an optional boolean property `empty`. When `empty: true` is set, an empty string (`""`) is considered valid and bypasses the other string checks (such as `min`, `max`, `pattern` and `enum`).
- `v.compile(schema)` returns a validator function `check(value)` that returns `true` on successful validation or an array of error objects on failure. Each error object has `type`, `expected`, `actual` and `message` fields.


- For a string schema with `enum: ["male", "female"]` and `empty: true`, validating `"human"` returns one error object whose `type` is `"stringEnum"`, `expected` is `"male, female"`, `actual` is `"human"`, and `message` is a string.
