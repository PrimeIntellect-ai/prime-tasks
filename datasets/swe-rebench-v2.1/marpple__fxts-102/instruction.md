Add `min` and `max` functions
# Suggestion

<!--
  Please fill in each section completely. Thank you!
-->

## ⭐ Suggestion

<!-- What would you like to be added? -->

## 💻 Use Cases

```ts
min([5, 3, 1]); // 1;
min([5, NaN, 1]); // NaN;

max([1, 3, 5]); // 5;
max([1, NaN, 1]); // NaN;
max([1, Infinity, 1]); // Infinity;

await min(toAsync([5, 3, 1])); // 1;
await max(toAsync([1, 3, 5])); // 5;
```
