Rule proposal: prevent some DOM elements from having children or dangerouslySetInnerHTML
There are some HTML elements that are normally self-closing (e.g. `img`, `br`, `hr`). If you try to give these children, React will give you a warning like

> Invariant Violation: img is a void element tag and must neither have `children` nor use `dangerouslySetInnerHTML`.

It would be nice to have a rule enforcing this.

Bad:

``` jsx
<img src="path/to/img.jpg">
  Children
</img>
```

``` jsx
<img src="path/to/img.jpg" dangerouslySetInnerHTML={{ __html: 'HTML' }} />
```

``` jsx
<img src="path/to/img.jpg" children="Children" />
```

Good:

``` jsx
<img src="path/to/img.jpg" />
```

The full list that React uses can be found:
- https://github.com/facebook/react/blob/85dcbf83/src/renderers/dom/shared/ReactDOMComponent.js#L421
- https://github.com/facebook/react/blob/85dcbf83/src/renderers/dom/shared/ReactDOMComponent.js#L449

Which comes out as:
- `area`
- `base`
- `br`
- `col`
- `embed`
- `hr`
- `img`
- `input`
- `keygen`
- `link`
- `menuitem`
- `meta`
- `param`
- `source`
- `track`
- `wbr`

### Additional contract requirements

- Register the rule in the plugin’s public rule registry under the name `void-dom-elements-no-children`.
