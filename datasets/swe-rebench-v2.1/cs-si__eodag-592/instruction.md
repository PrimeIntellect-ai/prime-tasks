Add keywords to discovered product types
Automatically add default keywords to discovered product types to help finding them using [guess_product_type()](https://eodag.readthedocs.io/en/stable/api_reference/core.html#eodag.api.core.EODataAccessGateway.guess_product_type).
See also [Guess a product type documentation](https://eodag.readthedocs.io/en/stable/notebooks/api_user_guide/4_search.html#Guess-a-product-type)

### Additional contract requirements

- For a discovered collection with id `foo_collection`, keywords `foo` and `bar`, and summaries containing instruments `baz`, constellation `qux,foo`, platform `quux`, `corge`, and `bar`, and processing level `grault`, the returned `product_types_config["foo_collection"]["keywords"]` must be a comma-separated string that splits into exactly 8 entries and includes `foo_collection`, `foo`, `bar`, `baz`, `qux`, `quux`, `corge`, and `grault`.
