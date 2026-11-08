boolean :: a -> a -> Boolean -> a
We have [`S.ifElse`][1], but we currently lack straightforward case folding for the `Boolean` type ([`S.maybe`][2] and [`S.either`][3] provide case folding for `Maybe a` and `Either a b` respectively).

I think `S.boolean` would be a good addition to the library.

```javascript
> S.boolean ('false') ('true') (false)
'false'

> S.boolean ('false') ('true') (true)
'true'
```

The one thing I very much dislike about the function is that one must learn that the constructors are essentially defined in `false | true` order rather than in `true | false` order. This is arbitrary, and does not match the argument order of `S.ifElse`. If we decide to add this function we should make it consistent with Haskell's [`bool`][4], so some confusion is unavoidable.


[1]: https://sanctuary.js.org/#ifElse
[2]: https://sanctuary.js.org/#maybe
[3]: https://sanctuary.js.org/#either
[4]: https://hackage.haskell.org/package/base-4.11.1.0/docs/Data-Bool.html#v:bool
