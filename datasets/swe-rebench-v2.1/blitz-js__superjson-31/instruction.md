Support circular references
CC https://github.com/blitz-js/superjson/pull/6#issuecomment-659243309

At the moment, the following throws a `Error: Circular Reference detected`.

```ts
const a = { role: 'parent', children: [] as any[] };
const b = { role: 'child', parent: [a] };
a.children.push(b);
SuperJSON.serialize(a); // throws
```

We could leverage the behaviour proposed in #8 to make it return the following, instead:

```js
{
  value: {
    a: {
      role: 'parent',
      children: [
        { role: 'child', parent: [null] }
      ]
    },
  },
  meta: {
    identities: {
      a: ["a.children.0.parent.0"]
    }
  }
}
```

This should then be easily revivable.

This is a payload that the regular `JSON.stringify` can't serialise, so I don't think it's a big problem we change the `value` payload here.

### Additional contract requirements

The serialized `meta` object records object identities under these exact keys:

- `referentialEqualities`: an object mapping the stringified path of the first
  occurrence of each repeated (non-root) object to an array of the stringified
  paths of its other occurrences.
- `referentialEqualitiesRoot`: an array of the stringified paths at which the
  root object reappears (i.e. circular references back to the root).

For the circular example above, `meta` is exactly:

```js
{
  referentialEqualitiesRoot: ['children.0.parents.0'],
}
```
