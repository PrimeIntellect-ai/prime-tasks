mapMaybe on something else than an array ?
Hello,

Currently this is available:
```js
S.map(S.get(S.is(Number), 'c'))({a: {c: 1}, b: {}}); // {a: Just(1), b: Nothing}
```

But this is not:
```js
S.mapMaybe(S.get(S.is(Number), 'c'))({a: {c: 1}, b: {}}); // would return {a: 1}
```

I was wondering if `mapMaybe` could be extended to operate the same way as `map`?
