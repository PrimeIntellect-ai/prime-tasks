Add an assertion for same members where order is important
I've come to discover that it's not straightforward to test that an array has the same members, and that those members are in the expected order. Consider this base example:

```js
var a = {};
var b = {};
var list = [ a, b ];
```

All of the assertions around "members" all explicitly do not consider order, but it would be really convenient to be able to assert that too:

```js
// no idea what to call this assertion
assert.sameExactMembers(list, [ a, b ]);
```

My use-case is that I have an internal list that I can retrieve. In one case I return the list unsorted. (so `sameMembers` works great) In the other case, I am sorting it in a specific way, so I want to assert that my sort worked as expected.

I am using `deepEqual` now, but the member objects can be fairly big/deep and it's very inefficient to traverse these objects, especially since I have the direct object refs in my tests.

```js
// in my case, a & b could be huge, so would prefer not traverse them
assert.deepEqual(list, [ a, b ]);
```

Another option is that I can just use `strictEqual` on each item in the array, but that gets unwieldy quickly imo:

```js
// only 2 in this case... but it's copy-pasta and ugly beyond a few members
assert.strictEqual(list[0], a);
assert.strictEqual(list[1], b);
```

### Additional contract requirements

- Provide `assert.sameOrderedMembers(actual, expected)` and the BDD chain `.ordered.members(expected)` in the `expect` and `should` interfaces. These assertions succeed when the arrays have the same length and corresponding members in the same order, and fail when their order differs.
- Ordinary ordered comparisons use direct equality for elements: two separately allocated objects with identical contents do not match. Existing `sameMembers` assertions continue to compare members without regard to order.
