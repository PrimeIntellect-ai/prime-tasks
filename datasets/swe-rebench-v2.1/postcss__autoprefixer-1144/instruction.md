[css-grid] `place-self` can be translated
I'm kicking myself for not realizing this while we were working on the align/justify-content/items warnings >_<

## Input CSS

```css
.grid > * {
  place-self: center;
}
```

## Current Output CSS

```css
.grid > * {
  place-self: center;
}
```

## Expected output CSS

```css
.grid > * {
  -ms-grid-row-align: center;
  -ms-grid-column-align: center;
  place-self: center;
}
```

### Additional contract requirements

- When a `place-self` declaration has two values, the first value must be used for `-ms-grid-row-align` and the second value for `-ms-grid-column-align`, with the original `place-self` declaration kept after them.
- Running the same stylesheet through Autoprefixer again must not add a second `-ms-grid-row-align` / `-ms-grid-column-align` pair for an existing `place-self` declaration.
