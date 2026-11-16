Link `item` type should be `application/geo+json`
Hi!

Pystac is not using [the **preferred** media type for link of rel `item` which should be `application/geo+json` rather than `application/json`](https://github.com/radiantearth/stac-spec/blob/master/commons/links.md#hierarchical-relations): https://github.com/stac-utils/pystac/blob/2261b55ffbac6b52e6f56434bfd5508455dc3ac6/pystac/link.py#L478
Is there a reason for that?

Thank you

### Additional contract requirements

- `Link.item(item: Item, title: str | None = None)` returns a `Link` whose `rel` is `pystac.RelType.ITEM` and whose `media_type` is `pystac.MediaType.GEOJSON` (`"application/geo+json"`).
