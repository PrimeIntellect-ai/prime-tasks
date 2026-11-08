d3.flatGroup
Like array.flatMap, but for d3.group. For example d3.flatGroup(data, fa, fb) would return [[keya1, keyb1, values], [keya2, keyb2, values], …]. Useful for simple iteration…

```js
for (const [species, sex, group] of d3.flatGroup(penguins, d => d.species, d => d.sex)) {
  …
}
```

Maybe there would be a d3.flatRollup too.
