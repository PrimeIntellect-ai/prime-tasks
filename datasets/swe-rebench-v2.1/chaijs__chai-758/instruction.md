Unexpected meaning of `deep` flag in `property` assertion
There's an inconsistency with the meaning of the `deep` flag. Consider these examples:

```js
const obj = {a: 1};
expect(obj).to.deep.equal({a: 1});  // Currently passes thanks to deep equality
expect([obj]).to.have.deep.members([{a: 1}]);  // Currently passes thanks to deep equality
expect([obj]).to.deep.include({a: 1});  // Will pass thanks to deep equality once Issue #743 is fixed
expect({foo: obj}).to.deep.include({foo: {a: 1}});  // Will pass thanks to deep equality once Issue #743 is fixed
expect({foo: obj}).to.have.deep.property('foo', {a: 1});  // Fails due to using strict equality
```

The reason the last example fails is because the `deep` flag has a different meaning when applied to the `.property` assertion than it does when applied to any other assertion. Instead of switching from strict to deep equality, the `deep` flag unlocks the ability for the developer to use dot or bracket notation in their `.property` assertion:

```js
const obj = {a: 1};
expect({foo: obj}).to.have.deep.property('foo.a', 1);
```

That's pretty cool, but the inconsistency of the `deep` flag creates a confusing developer experience and brings sadness to my soul. It also makes it impossible for other assertions such as `.include` to internally leverage `.property` by passing along the `deep` flag, as noted in https://github.com/chaijs/chai/issues/743#issuecomment-230186471.

I propose the following breaking change:

- Make the `deep` flag perform a deep equality comparison when used with the `.property` assertion.
- Add either a `nested` or `inner` flag to inherit the old behavior of the `deep` flag, allowing dot or bracket notation in the `.property` assertion.

Examples:

```js
const obj = {a: 1};
expect({foo: obj}).to.have.deep.property('foo', {a: 1});
expect({foo: obj}).to.have.nested.property('foo.a', 1);

const obj2 = {a: {b: 2}};
expect({foo: obj2}).to.have.deep.nested.property('foo.a', {b: 2});
```
