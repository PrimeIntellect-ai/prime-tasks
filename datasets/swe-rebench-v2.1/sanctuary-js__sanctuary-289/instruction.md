curry2 :: ((a, b) -> c) -> a -> b -> c
Now that Sanctuary is close to being an alternative to Ramda rather than a library intended to be used alongside it, we should consider which Ramda functions we would miss were we to remove Ramda from our projects. [`R.curry`][1] and [`R.curryN`][2] are certainly important functions. [`def`][3] performs currying, of course, but not every project which depends on Sanctuary also depends on sanctuary-def.

The type signatures of these Ramda functions are misleading:

```haskell
curry  :: (* -> a) -> (* -> a)
curryN :: Number -> (* -> a) -> (* -> a)
```

Accurate type signatures are an important tool for reasoning about functions. The Sanctuary functions would be much simpler:

```haskell
curry2 :: ((a, b) -> c) -> a -> b -> c
curry3 :: ((a, b, c) -> d) -> a -> b -> c -> d
curry4 :: ((a, b, c, d) -> e) -> a -> b -> c -> d -> e
curry5 :: ((a, b, c, d, e) -> f) -> a -> b -> c -> d -> e -> f
```

We must choose the maximum supported arity. I don't think it's necessary to go all the way to `curry5`; `curry2` and `curry3` should suffice. If you call recall using `R.curry` or `R.curryN` to produce a function of arity greater than 3, please speak up.

:curry:


[1]: http://ramdajs.com/0.22.1/docs/#curry
[2]: http://ramdajs.com/0.22.1/docs/#curryN
[3]: https://github.com/sanctuary-js/sanctuary-def
