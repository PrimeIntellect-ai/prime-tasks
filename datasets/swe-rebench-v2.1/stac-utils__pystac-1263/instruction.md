Bubble up exception in validators.resolve_from_url
So that I don't bury the (causal but not related) lead, the geojson.org schemas are unreachable (e.g. https://geojson.org/schema/Feature.json).

I discovered this when validating a pystac Item (pystac 1.1.0). The exception that I _correctly_ saw was:

```
File ".../python3.9/site-packages/jsonschema/validators.py", line 779, in resolve_from_url
    raise exceptions.RefResolutionError(exc)
jsonschema.exceptions.RefResolutionError: HTTP Error 404: Not Found
```

However, the specific URL is nowhere to be found in the exception. It would be really useful to have this information bubbled up in `exc` so that the developer doesn't have to go digging through the debug stack.

Thanks!
