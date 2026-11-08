onda search optimize with expand=Metadata
Avoid per-product metadata query using https://catalogue.onda-dias.eu/dias-catalogue/Products?$expand=Metadata link documented in
https://www.onda-dias.eu/cms/knowledge-base/odata-querying-products-showing-all-metadata-together-with-their-properties/.

Use a new `ODataV4Search` plugin configuration option, `per_product_metadata_query` (bool) to specify that per-product metadata query is no more needed.

See also https://github.com/CS-SI/eodag/issues/606#issuecomment-1399962814

### Additional contract requirements

When Onda search results include expanded metadata, that metadata is available on the returned products without separate per-product requests. The `per_product_metadata_query` option controls separate requests: `false` skips them and `true` enables them. When enabled, values returned for a product are available in that product's metadata.
