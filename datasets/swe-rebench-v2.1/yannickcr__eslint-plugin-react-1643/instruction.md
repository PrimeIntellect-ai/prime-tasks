Does jsx-pascal-case break <script crossorigin src="..."></script>?
Using prettier-eslint with react/recommended.
Trying to set script tags within JSX.
[React recommends](https://reactjs.org/docs/cross-origin-errors.html) adding `crossorigin` attribute.
Prettier keeps pascal-casing the attribute to `crossOrigin`.

Possible bug?

### Additional contract requirements

- When `<div crossorigin />` is checked, report `Invalid property 'crossorigin' found on tag 'div', but it is only allowed on: script, img, video`.
