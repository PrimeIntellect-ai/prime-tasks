Do something when STAC endpoint url ends with "/"
Hi,

When the STAC enpoint ends with "/", random things crashes in pystac.
```py
from pystac_client import Client
api1 = Client("https://some-stac-api.org/")  # erratically works
api2 = Client("https://some-stac-api.org")  # works
```
Maybe it could be more user/developer friendly to throw an exception when the enpoint is badly formed (I spent like 30 minutes figuring out why, I guess its a classic for newcomers).
Or, fix the url, or use urllib or something else to concatenate URL?

### Additional contract requirements

- When `Client.open("http://pystac-client.test/")` is used, opening must succeed, and `get_collections()` must request `http://pystac-client.test/collections`.
