fromMaybe_ :: (() -> a) -> Maybe a -> a
We added `maybe_`, a "lazy" version of [`maybe`][1], in #285. `maybe` is a convenient function for situations in which one wants to `map` then apply [`fromMaybe`][2]. It seems to me we should also provide a "lazy" version of `fromMaybe`. Otherwise we'll end up writing `S.maybe_(thunk, S.I, m)` in some cases, which seems a bit strange.

Do you agree?


[1]: https://sanctuary.js.org/#maybe
[2]: https://sanctuary.js.org/#fromMaybe
