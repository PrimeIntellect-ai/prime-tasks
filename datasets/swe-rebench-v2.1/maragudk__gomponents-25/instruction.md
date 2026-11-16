Implement remaining section elements as helpers
https://developer.mozilla.org/en-US/docs/Web/HTML/Element#Content_sectioning

- address
- article
- aside
- footer
- header
- hgroup
- main
- nav
- section

### Additional contract requirements

Add these public functions in package `el` (import path `github.com/maragudk/gomponents/el`). Each takes a variadic list of `g.Node` values, which may be empty, and returns a `g.NodeFunc` representing the corresponding HTML element. Any supplied nodes are rendered as the content of that element.

- `Address(children ...g.Node) g.NodeFunc` for `<address>`
- `Article(children ...g.Node) g.NodeFunc` for `<article>`
- `Aside(children ...g.Node) g.NodeFunc` for `<aside>`
- `Footer(children ...g.Node) g.NodeFunc` for `<footer>`
- `Header(children ...g.Node) g.NodeFunc` for `<header>`
- `HGroup(children ...g.Node) g.NodeFunc` for `<hgroup>`
- `Main(children ...g.Node) g.NodeFunc` for `<main>`
- `Nav(children ...g.Node) g.NodeFunc` for `<nav>`
- `Section(children ...g.Node) g.NodeFunc` for `<section>`
