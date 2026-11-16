mark entry point custom element when returning `metadata`
## Type of Change

<!-- Delete what does not apply -->

- New Feature Request

## Summary
It would be great for returned metadata to mark the initial custom element as the entry point, which can be helpful for more [app like usages of WCC](https://github.com/ProjectEvergreen/wcc/pull/73/files#diff-ace925ac48f91c9439187a9ba10fb1e60aebad19e14519a42d745d14d0651438R35).

## Details
For example
```js
const { metadata } = await renderToString(new URL('./src/pages/home.js', import.meta.url));

/*
 * {
 *   metadata: [
 *     'wcc-home': { instanceName: 'HomePage', moduleURL: [URL], entry: true },
 *     'wcc-footer': { instanceName: 'Footer', moduleURL: [URL] },
 *     'wcc-header': { instanceName: 'Header', moduleURL: [URL] },
 *     'wcc-navigation': { instanceName: 'Navigation', moduleURL: [URL] }
 *   ]
 * }
 *
```

However, if there is no `tagName` provided, like for a layout route or page, the next level of custom elements should be used instead.

### Additional contract requirements

- The metadata returned by `renderToString` and `renderFromHTML` exposes, for every discovered custom element, a boolean property named `isEntry`. It is `true` for the entry point custom element(s) and `false` for every other discovered custom element.
- When the entry module defines its own custom element, that custom element is the entry point.
- When the entry module does not define a custom element (for example a layout or page module), the custom elements it directly imports are the entry points.
- For `renderFromHTML`, each module passed in the `elements` array is an entry point.
