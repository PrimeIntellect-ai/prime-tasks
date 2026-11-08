S.pluck documentation is incorrect
The documentation for [`pluck`](https://github.com/sanctuary-js/sanctuary/blob/0853d0a592233fd602e8167760e33812d1870fa8/index.js#L3044-L3045) states that it is equivalent to `map(prop(k), xs)`. This is only the case if `xs` is an `Array`.

Either the documentation should be changed, or `pluck` should be updated to handle Functors in general (matching [`R.pluck`](http://ramdajs.com/docs/#pluck)'s behavior).

Incidentally, `R.pluck` works for Arrays and indices as well as Objects and keys (for obvious reasons).

### Additional contract requirements

`S.pluck` must work for any Functor, not only Arrays. Given a key and a Functor of
objects, it returns a Functor of the same type whose contents are the values of that
key:

- `S.pluck('x', [{x: 1}, {x: 2}, {x: 3}])` is `[1, 2, 3]`.
- `S.pluck('x', S.Just({x: 1, y: 2, z: 3}))` is `S.Just(1)`.
- `S.pluck('x', S.Nothing)` is `S.Nothing`.
- If an element does not have a property named by the key, `S.pluck` throws a
  `TypeError`.

The documented type of `S.pluck` is
`pluck :: (Accessible a, Functor f) => String -> f a -> f b`.
