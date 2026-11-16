Autoprefixer processing comment to locally turn off grid polyfill continues to report IE related warnings
Given the following snippit of CSS

```css
.usps > ul {
  display : flex;
  // ...
}

@supports(grid-template-columns: repeat(auto-fit, minmax(200px, max-content))) {
  .usps > ul {
    /* autoprefixer grid: off */
    display               : grid;
    grid-gap              : 20px 10px;
    grid-template-columns : repeat(auto-fit, minmax(200px, max-content));
    justify-content       : center;
  }
}
```

Even though it is using the `/* autoprefixer grid: off */` processing comment, this particular block continues to raise a warning that " `IE does not support justify-content on grid containers` ." when conditionally applying grid styling.

Elevating the processing comment to the scope of the `@supports` block itself yields the same result. It continues to report warnings related to IE's grid implementation. Only using `/* autoprefixer: off */` in these places works as expected.

While that suffices in the current situation for my problem, it is highly non-desired that the entirety of Autoprefixer has to be turned off. This would start causing problems once these rules end up containing properties which _do_ need prefixing, requiring that e.g. an artificially split CSS rule be maintained where autoprefixer can still be turned off.

**Autoprefixer version** : 9.8.4

### Additional contract requirements

- A `/* autoprefixer grid: off */` comment inside a declaration rule suppresses IE grid-implementation warnings for declarations in that rule.
- A `/* autoprefixer grid: off */` comment on an enclosing `@supports` scope suppresses IE grid-implementation warnings in nested rules.
- A `/* autoprefixer grid: off */` comment disables grid processing only; unrelated declarations that require prefixes continue to be prefixed.
