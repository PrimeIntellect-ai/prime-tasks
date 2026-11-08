Move TemplateError to errors module
We have consolidated most of our exception classes in `pystac.errors` with the exception of `pystac.layout.TemplateError`. For consistency, it seems like it would be best to put that in `pystac.errors` as well. For backwards compatibility, we may want to keep it in `pystac.layout` and explicitly re-export it in `pystac.errors` until the next major release.

### Additional contract requirements

- `pystac.errors.TemplateError` is a public exception class (a subclass of `Exception`) that signals failures while converting a layout template string into data for `LayoutTemplate`, including when a required field such as an item's collection ID is missing.
- `pystac.TemplateError` is available at the top level of the `pystac` package and refers to the same exception class.
- `pystac.layout.TemplateError` remains available for backwards compatibility.
