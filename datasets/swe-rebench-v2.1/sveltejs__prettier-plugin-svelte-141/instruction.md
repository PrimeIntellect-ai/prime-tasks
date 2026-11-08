[MARKUP] text warped to next line inside tags.
### Input
```html
<h1>
  Svelte Materialify
  <small class="text-h5 d-block text--secondary">
    🔨 Under Construction
  </small>
</h1>
```

### Output
```html
<h1>
  Svelte Materialify <small class="text-h5 d-block text--secondary"> 🔨 Under
    Construction </small>
</h1>
```

The `🔨 Under Construction` should stay in one line, looks ugly otherwise.

### Additional contract requirements

When formatting the heading example, keep “Svelte Materialify” and its following inline `<small>` element on the same line. Keep “🔨 Under Construction” together on one line rather than splitting the phrase across lines.
