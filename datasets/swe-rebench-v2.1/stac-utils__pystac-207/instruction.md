Collection construction can cause unintended exception
Creating a collection like this:

```python
collection = Collection(
    collection_id,
    "Example for script interaction with PySTAC",
    {"spatial": [[0, 0, 1, 1]], "temporal": [[datetime.now().isoformat(), None]]},
    None,
    [],
    [],
    [],
    {},
    {},
    [],
    {},
)
```

causes the following stack trace:

```
Traceback (most recent call last):
  File "post-item-with-pystac.py", line 10, in <module>
    collection = Collection(
  File "/home/james/.local/lib/python3.8/site-packages/pystac/collection.py", line 73, in __init__
    super(Collection, self).__init__(id, description, title, stac_extensions, extra_fields,
  File "/home/james/.local/lib/python3.8/site-packages/pystac/catalog.py", line 93, in __init__
    self.set_self_href(href)
  File "/home/james/.local/lib/python3.8/site-packages/pystac/collection.py", line 99, in set_self_href
    [HIDDEN]
```

This should catch any input errors in a different place or otherwise error more effectively.

Thanks @jisantuc for the bug report!

### Additional contract requirements

- Constructing a collection with valid arguments, including a supplied `href`, must succeed; `get_self_href()` must return that href.
- Invalid required arguments should be reported as `ValueError`, not as an incidental `AttributeError` during initialization.
