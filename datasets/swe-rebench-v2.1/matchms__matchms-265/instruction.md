Add retention data filters
As discussed in #251 , adding RI and RT filters to clean the metadata in the spectrum object would be good.

One additional idea would be for the retention time filter to allow passing a conversion factor which converts the RT to seconds and use this as a canonical unit for RT?

### Additional contract requirements

Provide public `add_retention_time` and `add_retention_index` filters through `matchms.filtering`. For a non-negative numeric value in the corresponding canonical metadata field (`retention_time` or `retention_index`), the filter returns a spectrum whose corresponding field contains that value as a float.
