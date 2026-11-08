remove instanceof checks
Sanctuary's run-time type checking currently relies on `instanceof` checks. This guarantees that if a value passes type checking it will support all the expected operations.

If a function requires an argument of type `Maybe a`, for example, a Maybe created by a *different* version of Sanctuary will fail type checking (with a rather confusing error message). For example:

    TypeError: ‘fromMaybe’ requires a value of type Maybe as its second argument; received Just(42)

The problem with this approach is that it rejects *valid* values too. Requiring the *same* version of Sanctuary from two different paths results in two incompatible Sanctuary modules existing in memory:

```javascript
const S1 = require('./path/to/sanctuary-0.7.0');
const S2 = require('./another/path/to/sanctuary-0.7.0');

S1.fromMaybe(NaN, S2.Just(42));
// ! TypeError: ‘fromMaybe’ requires a value of type Maybe as its second argument; received Just(42)
```

When might this occur?

  - In the browser, when dealing with iframes.

  - In Node, when using the [vm][1] module. @raine and I both discovered this while building REPLs.

  - In Node, when `package-a` depends on both `sanctuary` and `package-b`, and `package-b` also depends on `sanctuary`. If `package-a` applies a `package-b` function which returns a Maybe, the Maybe will not be recognized by the `sanctuary` module required by `package-a`.

    Note that npm performs dependency deduplication, so if `package-a` and `package-b` depend on the same version of `sanctuary`, both will use __package-a/node\_modules/sanctuary__. *Relying* on deduplication is undesirable: it's an optimization which should not effect a program's behaviour.

__The first and second scenarios also affect built-in types such as Array.__ [`R.is`][2] is also affected by this issue, as discussed in ramda/ramda#1140.

Clearly we must avoid `instanceof` checks. What might we do instead? For built-in types we have `Object.prototype.toString` and [`R.type`][3]:

```javascript
> Object.prototype.toString.call([])
'[object Array]'
> R.type([])
'Array'
```

For Sanctuary types (and other custom types) we need a different approach.

We can't use `.constructor.name` because a type may have multiple constructors: Maybe has `Nothing` and `Just`, for example. Furthermore, there's no guarantee that two constructors with the same name are equivalent.

[HIDDEN]

Hat tip to @jethrolarson who has been giving this matter a lot of thought. [HIDDEN]

Solving the problems associated with `instanceof` checks is the most important issue I'd like to address in v0.8.0. I'd love to know what others think of this proposal. Counterproposals welcome!


[1]: https://nodejs.org/api/vm.html
[2]: http://ramdajs.com/docs/#is
[3]: http://ramdajs.com/docs/#type
[4]: https://en.wikipedia.org/wiki/Reverse_domain_name_notation
[5]: https://gist.github.com/jethrolarson/5eaad6d7b22b231741c9

### Additional contract requirements

- Existing operations which require a Maybe value must accept valid Maybe values created by an independently loaded copy of Sanctuary.
- Built-in values from another JavaScript realm must be recognized by their runtime type, rather than by constructor identity.
- Values from different constructors that share a custom type identity must be recognized as the same custom type; custom type checking must not depend solely on constructor names or constructor identity, and distinct type identities must remain distinguishable.
- Custom types declare their identity with a string-valued `@@type` property on their prototype; instances inherit that identity.
- Runtime type checking must not rely on `instanceof` identity checks.
