core: allow to control style tag insertion location
[Internally Griffel ensures its style tags are inserted in the correct order to provide deterministic results](https://github.com/microsoft/griffel/blob/main/packages/core/src/renderer/getStyleSheetForBucket.ts#L65). However, when used in an application that lazy loads code and styles, Griffel's style tags may become interleaved with the application's style tags, resulting in non-deterministic results.

This manifests in real-world applications that use lazy loading of React components (and CSS modules for application styles in this case but I don't think that's necessarily relevant) and Fluent UI React v9 for controls. In this case application authors want to override default Fluent styles with their own CSS but because their components are lazily loaded and they cannot control where Griffel styles are loaded in the document they cannot be guaranteed their styles will have greater specificity than Fluent's built in Griffel styles.

I've created a rough demo of this on Codesandbox: [Griffel Lazy Load](https://codesandbox.io/s/griffel-lazy-load-example-j53dfe)

With the default example, by inspecting the source, you can see how some application CSS is loaded in the document first, then Griffel styles, then more app CSS.

I'd like an API for Griffel that allows me to control where Griffel's style tags are inserted so I can ensure they are in the correct place relative to my application's styles.

### Additional contract requirements

- `createDOMRenderer(targetDocument, options)` must accept an optional `insertionPoint` element in `options`. When supplied, Griffel-generated style tags are inserted immediately after that element, ahead of following application styles.
- Generated style tags must retain Griffel's deterministic bucket ordering, including when an insertion point is supplied. Media-query style tags must follow the configured media-query comparison order.
