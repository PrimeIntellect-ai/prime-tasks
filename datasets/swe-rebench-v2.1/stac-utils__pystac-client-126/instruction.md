StacApiIO instance not propagated to CollectionClient instances
The `Client` creation methods (`from_file` & `open`) accept `headers` and `parameters` arguments that allow a user to automatically include header and query string parameter values in all requests made to an API. However, these arguments are not passed along to requests made by `CollectionClient` instances that are created from that same client.

So, the following request to the `/search` endpoint would include the `api_key` query string parameter:

```python
client = pystac_client.Client.open("https://some-domain/some/api", parameters={"api_key": "myapikey})
some_item = next(client.get_items())
```

...while the following request to `/collections/some-collection/items` will not:

```python
client = pystac_client.Client.open("https://some-domain/some/api", parameters={"api_key": "myapikey})
collection = client.get_collection("some-collection")
some_item = next(collection.get_items())
```

[HIDDEN]

### Additional contract requirements

When a `CollectionClient` is obtained from a `Client` using `get_collection` or `get_collections`, requests for that collection's items must include the query parameters and headers configured on the originating client.
