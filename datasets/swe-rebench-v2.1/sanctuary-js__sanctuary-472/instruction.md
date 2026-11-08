Add pipeK for monads
Ramda has Kleisli composition via [composeK](http://ramdajs.com/docs/#composeK) and [pipeK](http://ramdajs.com/docs/#pipeK). We probably only need one of those.

It is worth considering instead a specification for Categories as suggested in https://github.com/fantasyland/fantasy-land/issues/208 and implementing a Kleisli type that exposes its own `compose`.

This would mean `pipe` would be sufficient if it were implemented in terms of `compose`.

### Additional contract requirements

- Add a public function `pipeK`, exported as `S.pipeK` in the sanctuary library.
- `S.pipeK` takes two arguments: `fs`, a Foldable collection of unary functions each returning a value in a Chain monad, and `x`, an initial value in that same Chain monad (for example `S.Just` or `S.Nothing`).
- `S.pipeK(fs, x)` returns a value in the same Chain monad, obtained by left-to-right Kleisli composition of the functions in `fs` applied to `x`.
- The type signature of `S.pipeK` is `(Foldable f, Chain m) => f (Any -> m Any) -> m a -> m b`.
