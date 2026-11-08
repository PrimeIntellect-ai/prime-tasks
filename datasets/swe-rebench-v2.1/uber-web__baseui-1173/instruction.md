Allow adding a prefix to the href attribute of the side-nav
Currently the Link's href is set to item.itemId in the side-nav component. This makes it cumbersome if all Links need to be prefixed.

I can take this up if needed.

### Additional contract requirements

- `Navigation` accepts an optional `mapItem` prop: a function that receives each navigation item (including items inside nested `subnav` lists) and returns the item to render in its place.
- A caller must be able to add a prefix to the href values of side-navigation links. When `mapItem` returns an item with a changed `itemId`, the rendered link's `href` is built from the returned `itemId`, so a prefix added to every `itemId` appears in the href of every link, including nested ones.
