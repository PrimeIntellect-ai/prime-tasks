issue while working with Promise
```
const names = [{name: "Bob"}, {name: "Foo"}];
console.log("names:" + JSON.stringify(names));

Promise.all(
    names.map(n => {
        return Promise.resolve(n).then(n => {
            console.log("n:" + JSON.stringify(n));
            return n;
        })
    })
).then(namesBack => {
    console.log("namesBack:" + JSON.stringify(namesBack));
});
```

The code above results in this:

> names:[{"name":"Bob"},{"name":"Foo"}]
> n:{"name":"Bob"}
> n:{"name":"Foo"}
> namesBack:[{"name":"Bob"},{"name":"Foo"}]

However If you only change the first line to use immutable like this:

```
const names = Immutable.from([{name: "Bob"}, {name: "Foo"}]);
console.log("names:" + JSON.stringify(names));

Promise.all(
    names.map(n => {
        return Promise.resolve(n).then(n => {
            console.log("n:" + JSON.stringify(n));
            return n;
        })
    })
).then(namesBack => {
    console.log("namesBack:" + JSON.stringify(namesBack));
});
```

The result differs:

> names:[{"name":"Bob"},{"name":"Foo"}]
> n:{"name":"Bob"}
> n:{"name":"Foo"}
> namesBack:[{"_45":0,"_81":0,"_65":null,"_54":null},{"_45":0,"_81":0,"_65":null,"_54":null}]

If we call asMutable() before .map call, then we are fine:

```
const names = Immutable.from([{name: "Bob"}, {name: "Foo"}]);
console.log("names:" + JSON.stringify(names));

Promise.all(
    names.asMutable().map(n => {
        return Promise.resolve(n).then(n => {
            console.log("n:" + JSON.stringify(n));
            return n;
        })
    })
).then(namesBack => {
    console.log("namesBack:" + JSON.stringify(namesBack));
});
```

result:

> names:[{"name":"Bob"},{"name":"Foo"}]
> n:{"name":"Bob"}
> n:{"name":"Foo"}
> namesBack:[{"name":"Bob"},{"name":"Foo"}]

We have no intent to mutate anything, so there should not be a need to call **asMutable**.
An enhancement to the "seamless-immutable" would be good.

### Additional contract requirements

- The `Immutable` function is exported by the module `seamless-immutable.development.js` (and by `src/seamless-immutable.js`).
- `Immutable.isImmutable(value)` is a public function that returns `true` when `value` is an immutable Seamless-Immutable object or array, and `false` otherwise.
- When `Immutable` is called with a Promise, it returns a new Promise that resolves to `Immutable(resolutionValue)`. The returned Promise is not itself made immutable, and a rejected input Promise's rejection reason is passed through unchanged.
- Mapping over an immutable array to produce Promises and passing the result to `Promise.all` resolves to the original values, without calling `asMutable()`.
