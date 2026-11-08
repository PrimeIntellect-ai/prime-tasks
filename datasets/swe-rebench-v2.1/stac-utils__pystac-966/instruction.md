Media type argument in `Item.get_links` method is ignored
The `media_type` argument is ignored when filtering the returned links with the `Item.get_links` method. It looks like it is short-circuited by the absence of a `rel` argument.

https://github.com/stac-utils/pystac/blob/e77cd0aa82b34803539ddaff310beadba9ca01e2/pystac/stac_object.py#L125-L133

I would expect to be able to filter on either (or both) `rel` and `media_type`. For example, I would expect the following to return the single link with an HTML media type, but it returns all links.

```
import pystac

item = pystac.read_file("https://planetarycomputer.microsoft.com/api/stac/v1/collections/landsat-c2-l2/items/LC09_L2SR_083122_20221230_02_T2")

html_links = item.get_links(media_type=pystac.MediaType.HTML)
for link in html_links:
    print(link.to_dict())

# Output:
# {'rel': 'collection', 'href': 'https://planetarycomputer.microsoft.com/api/stac/v1/collections/landsat-c2-l2', 'type': 'application/json'}
# {'rel': 'parent', 'href': 'https://planetarycomputer.microsoft.com/api/stac/v1/collections/landsat-c2-l2', 'type': 'application/json'}
# {'rel': <RelType.ROOT: 'root'>, 'href': 'https://planetarycomputer.microsoft.com/api/stac/v1/', 'type': <MediaType.JSON: 'application/json'>, 'title': 'Microsoft Planetary Computer STAC API'}
# {'rel': 'self', 'href': 'https://planetarycomputer.microsoft.com/api/stac/v1/collections/landsat-c2-l2/items/LC09_L2SR_083122_20221230_02_T2', 'type': 'application/geo+json'}
# {'rel': 'cite-as', 'href': 'https://doi.org/10.5066/P9OGBGM6', 'title': 'Landsat 8-9 OLI/TIRS Collection 2 Level-2'}
# {'rel': 'via', 'href': 'https://landsatlook.usgs.gov/stac-server/collections/landsat-c2l2-sr/items/LC09_L2SR_083122_20221230_20230101_02_T2_SR', 'type': 'application/json', 'title': 'USGS STAC Item'}
# {'rel': 'preview', 'href': 'https://planetarycomputer.microsoft.com/api/data/v1/item/map?collection=landsat-c2-l2&item=LC09_L2SR_083122_20221230_02_T2', 'type': 'text/html', 'title': 'Map of item'}
```
