support `innerHTML` in compiler for custom elements
## Type of Change

<!-- Delete what does not apply -->

- New Feature Request

## Summary
Although I did introduce a [`lightMode` configuration option](https://merry-caramel-524e61.netlify.app/docs/) for escaping the Shadow DOM `<template shadowroot="open">`, like for more "static" scenarios (e.g. documentation site), I've been thinking more about this implementation detail.

Specifically, I just realized now a better way to support this from userland would be to just let users pick which one works best for them?  So if you want to just ship static content, use `innerHTML`, if it is a more interactive scenario, and say you plan to use hydration, then use Shadow DOM.

## Details
This is important because browsers don't render a `<template>` tag, so anything inside them, like text content, will not be rendered without either using a browser that supports Declarative Shadow DOM, or by adding the polyfill.

This could also help play nicely with global CSS libraries like Tailwinds.

Will need to consider:
- If `lightMode` makes sense anymore?
- Document that without Shadow DOM, you can't use `:host` and `<slot>` etc.
- Is #16 relavant?
