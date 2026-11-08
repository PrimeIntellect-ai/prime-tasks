Add `size` function
# Suggestion

<!--
  Please fill in each section completely. Thank you!
-->

## ⭐ Suggestion

<!-- What would you like to be added? -->

## 💻 Use Cases

```ts
size(range(10, 16)); // 5
await size(toAsync(range(10, 16))); // 5
```

### Additional contract requirements

- Add a public function `size` to the package's public API, importable from the package entry point together with the existing helpers.
- `size(iterable)` accepts either an `Iterable<unknown>` (for example an array, a string, a `Set`, or the result of `range`) or an `AsyncIterable<unknown>` (for example the result of `toAsync`).
- For a synchronous iterable, `size` returns a `number` equal to the number of values the iterable produces.
- For an asynchronous iterable, `size` returns a `Promise<number>` that resolves to the number of values the iterable produces.
- `range(10, 16)` produces six values: 10, 11, 12, 13, 14, and 15. Therefore, both `size(range(10, 16))` and `await size(toAsync(range(10, 16)))` return 6; the example comments showing 5 are incorrect.
