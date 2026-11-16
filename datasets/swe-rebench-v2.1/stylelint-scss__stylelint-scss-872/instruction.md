Rule suggestion: `block-no-unnecessary-child-block`
I suggest a new Stylelint rule that reports a single block inside another block:

```scss
// BAD
.foo {
    .bar { … }
}

// GOOD
.foo .bar { … }
```

```scss
// BAD
.foo {
    &-bar { … }
}

// GOOD
.foo-bar { … }
```

```scss
// GOOD, there are multiple child blocks
.foo {
    .bar { … }
    &-baz { … }
}
```

```scss
// GOOD, the outer selector contains a comma
.foo,
.bar {
    &-baz { … }
}
```

### Additional contract requirements

- Add a rule function `rule(actual, _, context)` exported from `src/rules/block-no-redundant-nesting/index.js`; it returns a lint-processor function `(root, result)`.
- The exported rule function exposes a `ruleName` property whose value is the string `scss/block-no-redundant-nesting`.
- The exported rule function exposes a `messages` object property.
- The exported rule function exposes a `meta` object property with a `url` string.
- A block is reported only when its sole child is a single nested style rule with a single selector. A block that also contains declarations or at-rules is not reported, and Sass nested properties such as `font: { size: 16px; }` are not reported.
