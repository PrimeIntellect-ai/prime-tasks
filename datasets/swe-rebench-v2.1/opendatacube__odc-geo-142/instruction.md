Feature request: have save_cog_with_dask write band descriptions
Using `write_cog` we get band descriptions, but these don't currently show up if we use `save_cog_with_dask`. Could this be added? For example if I open a COG created with `write_cog` in a text editor I see a block like:
```
<GDALMetadata>
  <Item name="OVR_RESAMPLING_ALG">NEAREST</Item>
  <Item name="DESCRIPTION" sample="0" role="description">green</Item>
  <Item name="DESCRIPTION" sample="1" role="description">red</Item>
  <Item name="DESCRIPTION" sample="2" role="description">nir</Item>
  <Item name="DESCRIPTION" sample="3" role="description">swir1</Item>
  <Item name="DESCRIPTION" sample="4" role="description">swir2</Item>
  <Item name="DESCRIPTION" sample="5" role="description">swir3</Item>
  <Item name="DESCRIPTION" sample="6" role="description">swir4</Item>
  <Item name="DESCRIPTION" sample="7" role="description">swir5</Item>
  <Item name="DESCRIPTION" sample="8" role="description">swir6</Item>
  <Item name="DESCRIPTION" sample="9" role="description">tir1</Item>
  <Item name="DESCRIPTION" sample="10" role="description">tir2</Item>
  <Item name="DESCRIPTION" sample="11" role="description">tir3</Item>
  <Item name="DESCRIPTION" sample="12" role="description">tir4</Item>
  <Item name="DESCRIPTION" sample="13" role="description">tir5</Item>
</GDALMetadata>
```
Which means in QGIS I see band labels like "Band 04: swir1" whereas for a COG made by `save_cog_with_dask` I just see "Band 04"

cc @mplough-kobold @Kirill888

### Additional contract requirements

When the input DataArray stores band names in its `long_name` attribute, `save_cog_with_dask` must write those names as the corresponding band descriptions, in band order, so that raster consumers can expose them as band labels.
