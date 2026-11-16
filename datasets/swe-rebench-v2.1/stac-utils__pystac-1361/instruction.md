`get_all_collections` only goes one level deeper
I was trying to call `get_all_collections` to recursively get all collections within a root catalog. It turned out that only collections of the root catalog and its direct children are returned.

Looking at the code https://github.com/stac-utils/pystac/blob/ff67de3e4413422a417939bf49aa5b14428db35c/pystac/catalog.py#L455
```
def get_all_collections(self) -> Iterable[Collection]:
    """Get all collections from this catalog and all subcatalogs. Will traverse
    any subcatalogs recursively."""
    yield from self.get_collections()
    for child in self.get_children():
        [HIDDEN]
```
It seems that it's expected to only return collections from self and children.

Is it intentional or a bug?

### Additional contract requirements

- `Catalog.get_all_collections()` returns a generator that yields every `Collection` contained in the catalog and in all of its descendant sub-catalogs, traversing the hierarchy recursively.
- The traversal is depth-first: each sub-catalog's subtree is fully traversed before the next sibling sub-catalog is visited, and sibling sub-catalogs are visited in the order their child links appear.
- Errors raised while traversing a child catalog propagate to the caller.
