Permissively deserialize invalid temporal extents
I have been using the following code to process the [Maxar Open Data catalog](https://radiantearth.github.io/stac-browser/#/external/maxar-opendata.s3.amazonaws.com/events/catalog.json?.language=en) for several months now. It has been working until today. Now it throws a `ValueError: ISO string too short`. I am not sure if this a pystac or isoparser issue.

```python
from pystac import Catalog
url = "https://maxar-opendata.s3.amazonaws.com/events/catalog.json"
root_catalog = Catalog.from_file(url)
collections = root_catalog.get_collections()
collections = [collection.id for collection in collections]
```
![image](https://github.com/stac-utils/pystac/assets/5016453/5d2bab7c-a5dd-42c2-a6f7-6624878d292a)

### Additional contract requirements

- When deserializing a STAC Collection, accept a temporal `interval` given as a list of strings instead of a list of interval lists. Emit a `UserWarning`, normalize the value to a list of interval lists, and return the deserialized Collection without raising the reported `ValueError`.
