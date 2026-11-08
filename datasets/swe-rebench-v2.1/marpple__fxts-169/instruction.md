The empty array result of the `sum` function is '0'
# Suggestion

<!--
  Please fill in each section completely. Thank you!
-->

## ⭐ Suggestion

<!-- What would you like to be added? -->

If an empty array is entered as the argument value of the [sum function](https://fxts.dev/docs/sum), undefined is output.
Returning 0 seems more natural.

as-is
```ts
const result = pipe(
 [],
 sum
);

// result undefined
```


to-be
```ts
const result = pipe(
 [],
 sum
);

// result 0
```




## 💻 Use Cases

<!-- What do you want to use this for? -->

### Additional contract requirements

- For a synchronous numeric iterable, `sum` returns its arithmetic sum as a `number`; for an asynchronous numeric iterable, it returns a `Promise<number>` resolving to the sum.
- An empty iterable yields `0` (an asynchronous result resolves to `0`).
- `sum` can be used as a curried step in `pipe`, for example `pipe([1, 2, 3], sum).
