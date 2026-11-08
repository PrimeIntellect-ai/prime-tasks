Format double and overriding default formats
I have a use case that is using double numbers in the spec for monetary values.  Given that float is so imprecise, it would seem more valid to me to cast these to Decimal() from the decimal module.

btw, DEFAULT_FORMATS specifies both 'double' and 'float' format to the float()

Currently bravado-core does not allow you to override the DEFAULT_FORMATS, of course I can rename my spec format to decimal and get this to work for my implementation.  But I guess this brings up two questions:

1) Should you be able to override the DEFAULT_FORMATS in practice?
2) Should perhaps the default for double be to use the Decimal() class?

Thanks for sharing this awesome module.

### Additional contract requirements

- When a caller registers a user-defined `SwaggerFormat` through `Spec.from_dict` using `config={'formats': [...]}`, and its format name matches a built-in format, the user-defined format takes precedence. Its `to_python` and `to_wire` callbacks are used for conversions to and from the wire.
