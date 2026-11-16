NotImplementedError: No link with "rel" type of "search" could be found in this catalog
Raising issue here as suggested in https://github.com/stac-utils/pystac/issues/736#issuecomment-1041563811

**Original:**
I have created a local catalog as explained in tutorial https://pystac.readthedocs.io/en/1.0/tutorials/how-to-create-stac-catalogs.html, and I can access the items normally (even stack them with stackstac). However, when I try to search items through pystac-client, I receive the error, saying that I don't have a 'search' link:
NotImplementedError: No link with "rel" type of "search" could be found in this catalog

I couldn't find in pystac documentation how to create such search endpoint for a local catalog. Is it even possible ?

**Reply** posted by @duckontheweb in https://github.com/stac-utils/pystac/issues/736#issuecomment-1041563811_

@cordmaur The `"search"` link is defined in the STAC API Spec and would not be a part of a static catalog since it would require some kind of backend to implement all of the search capabilities.

I think it would be worth raising this issue in the `pystac-client` repo since `pystac-client` claims to be "A Python client for working with [STAC](https://stacspec.org/) Catalogs and APIs" and should probably be able to handle this gracefully.

### Additional contract requirements

- When a catalog does not advertise search support, the `NotImplementedError` message raised by a search attempt must contain the exact phrase `does not support search`.
