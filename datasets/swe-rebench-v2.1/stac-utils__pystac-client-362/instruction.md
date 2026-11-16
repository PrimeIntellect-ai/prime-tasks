GET request with "query" parameter throws exception
This succeeds as a POST, but fails as a GET. My guess is there's a problem with double-encoding like there was for intersects, but I haven't looked into it at all.

```
from pystac_client import Client

Client.open("https://planetarycomputer.microsoft.com/api/stac/v1").search(
                method="GET",
                query={"eo:cloud_cover":{"gte":0,"lte":10}},
            ).matched()
```
