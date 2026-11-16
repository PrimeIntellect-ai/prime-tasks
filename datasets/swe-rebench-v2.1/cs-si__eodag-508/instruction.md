Add S2_MSI_L1C productType to the USGS provider
When trying to download Sentinel2 images using the USGS provider, the "S2_MSI_L1C" product type is not recognized, even though it is available using the earth explorer website.

It would be great to add this one (and more precisely in my case I'd like that because I only got a bunch of failure when trying to do that using the peps provider...).

### Additional contract requirements

The USGS provider must make `S2_MSI_L1C` usable in the product search and download workflow: a product found for this type must resolve to the provider's Sentinel-2 dataset and be downloadable through USGS.
