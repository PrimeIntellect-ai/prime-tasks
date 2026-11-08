CDS source does not work with zipped vector data
### What happened?

The CDS source does not work with zipped vector data.

I think something is not right in the way earthkit handles this product.
I just tried, and geopandas is able to read the downloaded file: `geopandas.read_file("rgi6_vector.zip")`.

### What are the steps to reproduce the bug?

```python
import earthkit.data

collection_id = "insitu-glaciers-extent"
request = {
    "variable": "glacier_area",
    "format": "zip",
    "version": "6_0",
    "product_type": "vector",
}
ds = earthkit.data.from_source("cds", collection_id, request)
assert not isinstance(ds, earthkit.data.sources.empty.EmptySource)
```

### Version

0.5.1

### Platform (OS and architecture)

Darwin MacBook-Pro-3.local 22.6.0 Darwin Kernel Version 22.6.0: Wed Jul  5 22:21:56 PDT 2023; root:xnu-8796.141.3~6/RELEASE_X86_64 x86_64

### Relevant log output

_No response_

### Accompanying data

_No response_

### Organisation

B-Open / CADS-EQC
