(graphcache) - cache.resolve(parent, ...) doesn't seem to work
Hi guys,

After upgrade to `@urql/exchange-graphcache@3.3.1` `cache.resolve` doesn't seem to work always return `null` value.

```js
export const cache = cacheExchange({
  resolvers: {
    City: {
      name(parent, args, cache) {
        const id = cache.resolve(parent, "id");
        const name = cache.resolve(parent, "name");

        console.log({ id, name }); // null , null

        return `ID: ${id} - ` + name;
      }
    }
  }
});
```
`urql: 1.11.4`
`@urql/exchange-graphcache: 3.3.1`

**Steps to reproduce**
Check log tab
https://codesandbox.io/s/headless-wildflower-ynjsk

**The repo older version still work**
https://codesandbox.io/s/prod-monad-gmvyk

### Additional contract requirements

- `Store.keyOfEntity` (in `exchanges/graphcache/src/store/store.ts`) accepts an entity object, `null`, or a cache key string. It returns a string argument unchanged, returns `null` for `null` or for an entity that cannot be keyed, and otherwise returns the entity's canonical cache key.
- While a resolver or updater runs, the current parent entity's data is available on the resolver's `info` argument as `parent`, and `Store.keyOfEntity` returns the current parent's cache key when it is called with that exact parent object, even if the object is incomplete and cannot be keyed on its own.
