Deprecate the single value parameters (tag, role)
These two parameters are just shortcuts for the actual parameters (tags, roles). Removing them will keep consistent with `methods` (there isn't a `method` parameter), and users won't be confused with `example` and `examples` parameters (they are valid keys in [OpenAPI3](https://swagger.io/docs/specification/adding-examples/)).

- Remove usage of these params in examples and docs
- Add deprecate warning in 1.0
- Remove them in 1.1

### Additional contract requirements

In version 1.0, the single-value `role` and `tag` parameters continue to work as shortcuts for `roles` and `tags`. Using either parameter emits a `DeprecationWarning` that identifies the parameter as deprecated and indicates that it will be removed in version 1.1. Shipped documentation and examples must use the plural decorator parameters, not the single-value `role` or `tag` parameters.
