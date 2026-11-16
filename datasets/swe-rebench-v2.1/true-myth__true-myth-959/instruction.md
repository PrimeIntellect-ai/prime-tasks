[Task] all() does not preserve types in order
Instead of preserving the types in order as they are given it returns a union type of all `Task`s which makes it impossible without a type guard to differentiate between all items in the given Array.

```ts
const a = Task.resolve<string, Error>('');
const b = Task.resolve<number, Error>(42);
const c = Task.resolve<boolean, Error>(true);

// const d: Result<(string | number | boolean)[], Error>
const d = await all([a, b, c]);
// (parameter) e: (string | number | boolean)[] instead of [string, number, boolean]
d.map((e) => {
    // const f: string | number | boolean | undefined instead of const f: string
    const f = e[0];
});
```

---

My assumption was that it should work exactly like `Promise.all()`

```ts
const a = Promise.resolve<string>('');
const b = Promise.resolve<number>(42);
const c = Promise.resolve<boolean>(true);

// Correctly infers const d: [string, number, boolean]
const d = await Promise.all([a, b, c]);
// Correctly infers const e: string
const e = d[0];
```
