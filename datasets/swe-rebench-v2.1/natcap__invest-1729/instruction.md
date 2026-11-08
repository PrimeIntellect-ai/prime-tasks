Standardize field names in biophysical tables
If a biophysical table is an invest input that has a row for each landcover type, then all tables need a landcover column. Most models call this column `lucode`, but some do not:

* Habitat Quality: `lulc`
* Coastal Blue Carbon: `code`
* Crop Production: this one is kinda weird. There is a whole table devoted to mapping `lucode` to `crop_name`, and then the biophysical table (fertilization rate table) uses `crop_name`. Probably there is a reason for this, so maybe it's okay not to touch it.

I propose we change to `lucode`. And I guess that would be a breaking change so should go in a minor release.

### Additional contract requirements

- Coastal Blue Carbon’s preprocessing LULC lookup table must also use `lucode` as its landcover-code column.
- Habitat Quality’s generated rarity CSV files must have the header `lucode,rarity_value`.
