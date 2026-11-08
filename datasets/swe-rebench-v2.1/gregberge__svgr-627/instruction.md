Inline css var support
<!-- Love SVGR? Please consider supporting our collective: 👉  https://opencollective.com/svgr/donate -->


I just use a svg file which declares css variable in style attribute.

for example:
test.svg:
`<svg><path style="--index: 1"></path><path style="--index: 2"></path></svg>`

but it throws an error while transforming:   Expected identifier but found "-"

### Additional contract requirements

- When a CSS custom property declared in an SVG `style` attribute has a numeric value, the generated style object must contain that value as a number, not as a string (for example `--index: 1` yields the number `1`).
- Pixel values in CSS style declarations must be converted to numbers in the generated style object (for example `font-size: 24px` yields the number `24`).
