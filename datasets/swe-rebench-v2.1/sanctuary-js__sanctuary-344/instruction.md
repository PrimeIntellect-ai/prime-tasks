complement :: (a -> Boolean) -> a -> Boolean
This is a beautiful implementation:

```javascript
//    complement :: (a -> Boolean) -> a -> Boolean
[HIDDEN]
```

We tend not to use curried functions internally, so this is probably not the implementation we should choose. I do enjoy finding uses for partially applying `compose`, though. :)

### Additional contract requirements

- Add a public function `complement :: (a -> Boolean) -> a -> Boolean`, exported as `S.complement` from the Sanctuary library.
- `complement` is curried: `complement(pred)` returns a function that accepts the value, so both `complement(pred, x)` and `complement(pred)(x)` return the logical negation of `pred(x)`.
