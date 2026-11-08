Prevent SVG aria attributes from being removed
Is it possible with any combination of settings to prevent `aria-*` attributes from being remove from the `<svg>` tag when optimising?

I have tried all options that seem relevant to this but have had no luck so far:
```
.pipe($.svgo({
    addAttributesToSVGElement: true,
    removeUnknownsAndDefaults: false,
    cleanupAttrs: false,
    removeEmptyAttrs: false
}))
```

This is quite important as the `aria-labelledby` and `aria-describedby` attributes allow screen readers to interpret the content of inline SVG's.

### Additional contract requirements

- When optimising with the default plugin configuration, `aria-*` attributes on the root `<svg>` element (for example `aria-labelledby`) must be kept in the output with their values unchanged.
