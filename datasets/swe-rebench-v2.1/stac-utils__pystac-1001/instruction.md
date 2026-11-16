Add 'fully_resolve' back to STACObject
In https://github.com/stac-utils/pystac/commit/04c0d33bf2c24eec8f813fe86847f92c7bf29780 I removed the 'fully_resolve' methods as they weren't used in normalizing hrefs.

However, this is useful in another situation. I want to upgrade a collection of test files to 1.0. I wanted to do:

```python
collection = pystac.Collection.from_file("collection.json")
collection.fully_resolve()
collection.save()
```

which would upgrade everything (as save skips anything that is not resolved in memory)

We should add `fully_resolve` back in for this use case.
