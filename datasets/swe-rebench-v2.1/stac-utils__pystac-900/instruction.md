Normalize URLs and set link types for newly added entities
When you save a catalog it walks the tree and saves only those objects which are resolved...i.e., they are stored in memory. Which makes sense, no need to read the file in only to save it again.

However, when calling `normalize_hrefs` or `normalize_and_save`, all links are resolved and function mutates the entire tree.

This makes updates to a catalog difficult. If I have an existing catalog and add subcatalogs/items to it, it's hard to save those. I need to use `save_object`, but then have to include the code for generating the proper new self hrefs.  Also, when combined with `generate_subcatalogs` this becomes pretty tricky and I'm still trying to figure out the best way to do it.  I kept having trouble trying to set the self hrefs and link type to relative on a set of subcatalogs.

It seems like if I add a new entity to an existing catalog, part of that add should be to set the self_href, and the link type that points to it (relative or absolute), so that I can then later call just the `save` function on my catalog.   Since the only resolved item links are the new items I added this efficiently saves just the newly added items and ignores everything else.

Somewhat related to this is would be nice to be able to easily "unresolve" entities, which would allow me to save periodically - I could save the catalog, add some items, save again, add more items, etc.

### Additional contract requirements

- `Catalog.normalize_hrefs(root_href, strategy=None, skip_unresolved=False)` accepts an optional boolean `skip_unresolved` argument that defaults to `False`. When `skip_unresolved` is `True`, only links that are already resolved are processed and unresolved links are left unchanged.
- `Catalog.normalize_and_save(root_href, catalog_type=None, strategy=None, stac_io=None, skip_unresolved=False)` accepts the same optional boolean `skip_unresolved` argument, defaulting to `False`. With `skip_unresolved=True` only resolved objects are normalized and saved, while unresolved or missing references are left untouched. With `skip_unresolved=False`, saving may raise `FileNotFoundError` when an unresolved link is encountered.
