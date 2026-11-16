expect(array).to.not.include(obj) failing with constructors
This may be linked to https://github.com/chaijs/chai/issues/390, but I'm not sure so reporting this separately:

Environment:
  - Chai version: 3.5.0
  - Node version: 6.2.0

Test case:
```js
function SomeConstructor() {}
const instance1 = new SomeConstructor();
const instance2 = new SomeConstructor();

expect(instance1).to.not.equal(instance2) // => passes as expected

const arr = [instance1];
expect(arr).to.include(instance1) // => passes as expected
expect(arr).to.not.include(instance2) // => fails; unexpected
```

As a workaround, I can change the constructor to:
```js
function SomeConstructor() {
  this.uid = Symbol();
}
```
and `expect(arr).to.not.include(instance2)` will work fine.
