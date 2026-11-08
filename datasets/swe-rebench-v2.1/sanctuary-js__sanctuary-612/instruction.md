S.get and S.gets without first argument
Hello there, I'm relatively new at FP in JS and i'm finding this library quire useful.

I am a heavy Ramda user and two of the functions I use most are [`R.prop`](https://ramdajs.com/docs/#prop) and [`R.path`](https://ramdajs.com/docs/#path).

What I really like about both of them is that they allow me to get a value in a safe way.
If the prop or the path is missing in the provided object, `undefined` is returned.

It would be perfect if:
1) the prop/path exists, a `Just(value)` is returned
2) the prop/path does not exists a `Nothing` is returned

Your library implements an `S.prop` and an `S.props` having a different behavior.
Indeed in case 1 the value is returned, while in case 2 an error is thrown.

So in your documentation it is suggested to use the `S.get`/`S.gets` functions to access a property/path of uncertain objects.
But in such a case the functions signature is different because I need - first of all - to provide a predicate.

Eventually I ended up to use a combination of `monet.js` and `ramda` to obtain a function satisfying point 1 and 2 of my previous list.
For example, this is a possible solution (where R is ramda and Maybe is from monet).

```
const propMaybe = prop => R.pipe(
  R.prop(prop),
  Maybe.fromNull,
)
```

As I said at the beginning, I am quite new in the FP world, so I am sure I am missing the point. But wouldn't be useful a something like the function I described?

I think you have already something very similar that is `S.head`.

Thank you in advance for your answers.

### Additional contract requirements

Make the safe lookup available through the public API. It accepts a property name and then a map in two successive applications, and returns a `Just` containing the property's value when present or `Nothing` when absent. The caller must not need to provide a predicate. The public operation's name is not prescribed.
