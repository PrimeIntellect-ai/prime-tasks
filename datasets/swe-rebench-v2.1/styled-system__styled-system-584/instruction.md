All properties from parent category get included when applying an individual prop
I _think_ I've discovered a bug!

I noticed while working on Primer Components that it seems that all props that exist in a category get included when trying to include just one prop from that category.

For example, I've got some custom categories in Primer Components, one of them being `LAYOUT`:

```
export const LAYOUT = compose(
  styledSystem.width,
  styledSystem.height,
  styledSystem.minWidth,
  styledSystem.minHeight,
  styledSystem.maxWidth,
  styledSystem.maxHeight,
  styledSystem.overflow,
  styledSystem.verticalAlign
)
```

Note that `display` is purposefully excluded from `LAYOUT` because I've already included it in `COMMON`, a different custom category that I've made.

I noticed in my snapshots for our `Box` component that the `display` prop is implemented twice. I confirmed that this was happening by removing `COMMON` from my `Box` component (which previously had both `COMMON` and `LAYOUT`) and seeing if `Box` still gets the `display` prop (from `LAYOUT`) and it does.

Further, I tested out this:

```
export const LAYOUT = compose(
  styledSystem.width,
  styledSystem.height
)

```

and confirmed that a component importing the `LAYOUT` group of props is still able to use all the other props in the `layout` category in styled system, even though I've only included `width` and `height`.

I also tested renaming my custom group of props from `LAYOUT` to `ASDFG` to double check that this wasn't happening because of a naming clash, and confirmed that this still happens with a totally random name.

### Additional contract requirements

- `system(config)`, exported from `@styled-system/core`, returns a parser function that also exposes a shortcut method named after each property key present in `config`. Calling such a shortcut with a props object returns a style object containing only that property, ignoring every other property present on the input.
- The `styled-system` package exports a `width` function that processes only the `width` prop and ignores other props such as `height` and `maxWidth`.


- When called with `{ width: 1, height: 32, maxWidth: 768 }`, the `width` function must return `{ width: '100%' }`.
