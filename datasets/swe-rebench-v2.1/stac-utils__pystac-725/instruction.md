catalog.save(dest_href) has unexpected results for pystac.CatalogType.RELATIVE_PUBLISHED
I really appreciate the recently added functionality to save a catalog to a target location. I was hoping to use this for the case of a static RELATIVE_PUBLISHED catalog in a github repository, but working on it locally via git clone (but not a full catalog copy as described here https://github.com/stac-utils/pystac/issues/137). To-date, for new catalogs I've accomplished this by 1. writing a version locally, 2. manually changing the self link in the catalog, 3. then publishing by pushing to github.

In pystac=1.1 using catalog.save(pystac.CatalogType.RELATIVE_PUBLISHED, dest_href=local_dir) from https://github.com/stac-utils/pystac/pull/565. cc @duckontheweb @volaya

I've noticed two oddities. 1. subcatalogs or collections get a *subfolder* for example `.collection.json/` which seems a bit odd.
```
local_stac
├── catalog.json
└── collection1
    └── collection.json
        ├── collection.json
        └── item1
            └── item1.json
```

And 2. it seems that items are written with a `self` link, which i believe is unnecessary according to https://pystac.readthedocs.io/en/latest/concepts.html#relative-published-catalogs.

A reproducible example is below modified from https://github.com/stac-utils/pystac/issues/90
```python
import pystac
from datetime import datetime
import os.path

published_href = 'https://raw.githubusercontent.com/stactools-packages/sentinel1/main/examples/catalog.json'
local_href = './local_stac/catalog.json'
local_dir = os.path.dirname(local_href)

RANDOM_GEOM = {
    "type": "Polygon",
    "coordinates": [
        [
            [-2.5048828125, 3.8916575492899987],
            [-1.9610595703125, 3.8916575492899987],
            [-1.9610595703125, 4.275202171119132],
            [-2.5048828125, 4.275202171119132],
            [-2.5048828125, 3.8916575492899987],
        ]
    ],
}

RANDOM_BBOX = [
    RANDOM_GEOM["coordinates"][0][0][0],
    RANDOM_GEOM["coordinates"][0][0][1],
    RANDOM_GEOM["coordinates"][0][1][0],
    RANDOM_GEOM["coordinates"][0][1][1],
]

RANDOM_EXTENT = pystac.Extent(
    spatial=pystac.SpatialExtent.from_coordinates(RANDOM_GEOM["coordinates"]),
    temporal=pystac.TemporalExtent.from_now()
)

catalog = pystac.Catalog(id="root",
                         description="root test",
                         #href=local_href,
                         href=published_href, # NOTE: remote published location
                         catalog_type=pystac.CatalogType.RELATIVE_PUBLISHED)

spatial_extent = pystac.SpatialExtent(bboxes=[RANDOM_BBOX])
temporal_extent = pystac.TemporalExtent(intervals=[[datetime.utcnow(), None]])
collection_extent = pystac.Extent(spatial=spatial_extent, temporal=temporal_extent)

collection1 = pystac.Collection(
    id="collection1",
    description="test collection 1",
    extent=collection_extent,
    license="CC-BY-4.0",
)

catalog.add_child(collection1)

item1 = pystac.Item(id="item1", geometry=RANDOM_GEOM, bbox=RANDOM_BBOX, datetime=datetime.utcnow(), properties={})
item1.add_asset("ortho", pystac.Asset(href="/some/ortho.tif"))
collection1.add_item(item1)

catalog.validate_all()

catalog.save(dest_href=local_dir)
```
