Support `<Tiles>` to not expand in width
## Description

Currently the children of `<Tiles>` will always take the available width (`1fr`) and only have a lower bound (`itemMinWidth`). There is no way to have children to stay at a certain width. This is especially useful if you have multiple `Tiles` on a page an want them to look the same.

## Proposal

Expand the API with properties to change from stretching to the available width to a given width.

## Implementation

Change grid template. Currently:

```js
`repeat(auto-fit, minmax(min(${itemMinWidth}, 100%), 1fr))`
```

to

```js
[HIDDEN]
```

### Additional contract requirements

- Callers can choose a tile width so tiles do not expand to consume unused row space. The width may be supplied as `tilesWidth` or `width`, either as a CSS width or a theme size token.
- Callers can instead select a mode that lets tiles expand to use the available row width, with a chosen width still acting as the point at which tiles move to another row. This mode may be exposed as `stretch` or `fill`.
