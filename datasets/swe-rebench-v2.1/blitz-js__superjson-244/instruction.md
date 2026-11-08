referential equalities are unnecessarily noisy
given object

```ts
const obj = {
  children: [],
}
const input = {
  a: obj,
  b: obj,
};
```

It's key to say that path `b === a`, but it's redundant to say that `a.children === b.children`. This is currently the case


The above currently gives `refentialEqualities` of:

```json
{
  "a": [
    "b"
  ],
  "a.children": [
    "b.children"
  ]
}
```

Causes big complex payloads to be reallllyyyy noisy.
