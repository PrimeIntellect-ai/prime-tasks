xlink:href becomes xlink::href
#310 fixes `xlinkHref` attributes but breaks `xlink:href` by adding another colon:

```js
> require('preact-render-to-string').renderToString({constructor: undefined, type: 'use', props: {'xlink:href': 'hi'}})
'<use xlink::href="hi"></use>'
```

[HIDDEN]

### Additional contract requirements

- Render an attribute named `xlink:href` as `xlink:href`, without adding a second colon.
- Continue to render the camel-case attribute `xlinkHref` as `xlink:href`.
