Optional `convert`
Is it, or could it be, possible to have optional type conversion using the `convert` argument, with the same logic as validation?

Something like:

``` python
@attr.s
class Thing(object):
    x = attr.ib(default=None, convert=optional(float), validator=optional(validate_x))
```

Apologies if it's already supported; I just don't see how in the docs.

### Additional contract requirements

Provide `optional(converter)` as `attr.converters.optional`. It returns a callable that leaves `None` unchanged and applies the supplied converter to every non-`None` value; converter results and exceptions are preserved. The callable can be used as an attribute's `convert` argument.
