url_with_parameters omiting query filter values
Any filter search passed via `query=` appears to be stripped off the url returned by the `url_with_parameters` method. See example below.

```python
from pystac_client.item_search import ItemSearch

search = ItemSearch(
    url="https://planetarycomputer.microsoft.com/api/stac/v1/search",
    collections=["sentinel-2-l2a"],
    bbox=[88.214, 27.927, 88.302, 28.034],
    query={"eo:cloud_cover": {"lt": 10}}
)
search.url_with_parameters()
# 'https://planetarycomputer.microsoft.com/api/stac/v1/search?limit=100&bbox=88.214,27.927,88.302,28.034&collections=sentinel-2-l2a&query=eo:cloud_cover'
```
