Deprecate and remove `ValueCastable.lowermethod`
This isn't actually serving any useful purpose.

- Deprecation PR: N/A
- Removal PR: N/A (for milestone 0.6)

### Additional contract requirements

- Applying `ValueCastable.lowermethod` during the deprecation period emits a `DeprecationWarning`.
- A `ValueCastable` subclass may implement `as_value` without applying `ValueCastable.lowermethod`.
