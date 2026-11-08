`get_collection` always returns last collection with a local catalog
I am opening a local static STAC catalog as follows

```
  client = Client.open(catalog)
  collection = client.get_collection(collection_name)
```

This always returns the last collection in the catalog.

I think this clause [HIDDEN];

https://github.com/stac-utils/pystac-client/blob/main/pystac_client/client.py#L412
