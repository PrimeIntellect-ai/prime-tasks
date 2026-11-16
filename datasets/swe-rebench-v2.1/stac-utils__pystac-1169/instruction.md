Adding custom links between sibling catalogs creates absolute HREFs
In the following example, we have a `root` catalog which includes two sub-catalogs `a` and `b`. I now want to highlight a reference between the two siblings, which cannot be replaced by a parent-child link:

```python
import pystac

root = pystac.Catalog("root", "root")
a = pystac.Catalog("a", "a")
b = pystac.Catalog("b", "b")

root.add_child(a)
root.add_child(b)

a.add_link(pystac.Link("related", b))

root.normalize_and_save("test_out", pystac.CatalogType.SELF_CONTAINED)
```

Even when I now save it as "self-contained", I now have an absolute link from `a` to `b`:

```json
{
  "type": "Catalog",
  "id": "a",
  "stac_version": "1.0.0",
  "description": "a",
  "links": [
    {
      "rel": "root",
      "href": "../catalog.json",
      "type": "application/json"
    },
    {
      "rel": "related",
      "href": "/home/<user>/test_out/b/catalog.json"
    },
    {
      "rel": "parent",
      "href": "../catalog.json",
      "type": "application/json"
    }
  ],
  "stac_extensions": []
}
```

I would have expected something like that:
```json
...
   {
      "rel": "related",
      "href": "../b/catalog.json"
    },
...
```
I can't seem to get rid of the absolute links, even when using `stac copy` or similar commands.
