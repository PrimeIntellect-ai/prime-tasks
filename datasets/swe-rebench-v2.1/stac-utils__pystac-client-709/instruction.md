using StacApiIO with regular pystac breaks
I figured passing an instance of `StacApiIO` would be an easy way to add retries and request timeout handling to regular pystac but this does not work e.g.

```python
import pystac
from pystac_client.stac_api_io import StacApiIO

stac_io = None
stac_io = StacApiIO(timeout=60)
stac_object = pystac.read_file(href="collection.json", stac_io=stac_io)

print(stac_object.get_root().id)
```

fails with:
```
Traceback (most recent call last):
  File "/usr/lib/python3.8/runpy.py", line 194, in _run_module_as_main
    return _run_code(code, main_globals, None,
  File "/usr/lib/python3.8/runpy.py", line 87, in _run_code
    exec(code, run_globals)
  File "/home/bossie/PycharmProjects/openeo/openeo-geopyspark-driver/openeogeotrellis/test_pystac_client.py", line 30, in <module>
    test_stac_api_io_with_regular_pystac()
  File "/home/bossie/PycharmProjects/openeo/openeo-geopyspark-driver/openeogeotrellis/test_pystac_client.py", line 26, in test_stac_api_io_with_regular_pystac
    print(stac_object.get_root().id)
  File "/home/bossie/PycharmProjects/openeo/venv38/lib/python3.8/site-packages/pystac_client/collection_client.py", line 108, in get_root
    raise ValueError(
ValueError: `CollectionClient.root` is not have a valid `Client` object.
```

This is unexpected and seems like a violation of the Liskov substitution principle (CollectionClient IS-A pystac.Collection).

### Additional contract requirements

- A collection loaded through regular PySTAC with a supplied `StacApiIO` allows `get_root()` to return its root instead of raising the reported error.
- `StacApiIO` accepts a `timeout` keyword argument and stores the given value on its public `timeout` attribute, so that `StacApiIO(timeout=42).timeout == 42`.
- When a timeout is configured, HTTP requests made through `StacApiIO` use that timeout.
