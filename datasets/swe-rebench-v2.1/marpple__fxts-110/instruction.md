Add `juxt` function
# Suggestion

<!--
  Please fill in each section completely. Thank you!
-->

## ⭐ Suggestion

<!-- What would you like to be added? -->

Applies a list of function to a `Iterable/AsyncIterable` of values.

## 💻 Use Cases

<!-- What do you want to use this for? -->

```ts
juxt([Math.max, Math.min])(1,2,3,-4,5,6) // [6, -4]
```
