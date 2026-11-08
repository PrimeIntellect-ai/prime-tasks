tagBy :: (a -> Boolean) -> a -> Either a a
#348 prompted an interesting discussion which is still unfolding. I've had a related thought which I'd like to discuss separately to avoid derailing that pull request.

I dislike `ifElse`. Every time I use it I feel I'm missing some simple way to avoid conditional logic. In many cases Sanctuary *does* make it possible to avoid conditional logic. One can, for example, apply [`filter`][1] to a value of type `Maybe a` to avoid [`chain`][2] + conditional logic.

I would like to be able to *remove* `ifElse`. If this is unreasonable, though, it's natural to include `when` and `unless`.

There may be a better approach, though. I found [`tagBy`][3] in [XMonad.Util.Stack][4]. This would allow us to use the Either type for conditional logic:

```javascript
ifElse(odd, inc, dec) :: Number -> Number
when(odd, inc)        :: Number -> Number
unless(odd, dec)      :: Number -> Number
```

```javascript
compose(bimap(dec, inc), tagBy(odd)) :: Number -> Either Number Number
compose(map(inc), tagBy(odd))        :: Number -> Either Number Number
compose(bimap(dec, I), tagBy(odd))   :: Number -> Either Number Number
```

The `tagBy` forms are less terse but contain more information and are thus more flexible. The `Either Number Number` can be collapsed to a `Number` if desired, or the branches can be kept separate to facilitate additional conditional transformations.

I don't think it's necessary to choose between `ifElse` and `tagBy`. As much as I'm in favour of providing one and only one way to do a given thing, the "one true way" is sometimes less obvious and/or less clear than the alternative, particularly in simple cases. A good example is `complement`, which was recently added in #344. The "one true way" is to use `map(not)`, but it's not obvious that `map` lifts a function and that lifting `not` produces `(a -> Boolean) -> (a -> Boolean)`.

Regardless of what we decide to do with `ifElse`, `when`, and `unless`, I think `tagBy` is a sweet function! Do others agree?


[1]: https://sanctuary.js.org/#filter
[2]: https://sanctuary.js.org/#chain
[3]: http://hackage.haskell.org/package/xmonad-contrib-0.13/docs/XMonad-Util-Stack.html#v:tagBy
[4]: http://hackage.haskell.org/package/xmonad-contrib-0.13/docs/XMonad-Util-Stack.html
