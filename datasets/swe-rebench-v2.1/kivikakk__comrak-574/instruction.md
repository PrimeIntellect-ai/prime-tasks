Heading anchors should include the inert property
Screen readers can't handle the anchors as they are as they retain focus when you go to them, the output html should include the [`inert`](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Global_attributes/inert) property to prevent any interactibility since they're not a visible item in the page but a functional one in the hierarchy.

### Additional contract requirements

- Render each generated heading anchor with the bare `inert` attribute immediately after `<a` and before `href`, as in `<a inert href="..."`.
