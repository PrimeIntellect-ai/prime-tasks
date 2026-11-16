`is` can be fooled
```js
S.is(function Number () {}, 4)
// -> true
```

While documentation says:

`is :: TypeRep a -⁠> Any -⁠> Boolean`

Takes a type representative and a value of any
type and returns `true` iff the given value is of the specified type.
Subtyping is not respected.

### Additional contract requirements

- `S.is` takes a sanctuary-def `Type` value (for example `$.Number`, `$.Array($.Integer)`, `S.MaybeType($.Integer)`, or a custom `$.NullaryType`) as its first argument, rather than a type representative. It returns `true` iff the given value is a member of that type, with membership as defined by sanctuary-def's `$.test`.
- `S.is` must not report that a value belongs to a type merely because a supplied function has the same name as that type. For example, given a function named `Number` and the value `4`, the result must not be `true`; the result must reflect the specified type.
