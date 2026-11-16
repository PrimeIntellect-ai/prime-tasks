Allow prototypes to be ignored in deep comparisons
Relies on https://github.com/hapijs/hoek/pull/133. This is a semver minor change.

### Additional contract requirements

On deep equality assertions, `equal(expected, options)` and its `equals` alias must accept `{ prototype: false }` as a comparison option. When this option is supplied, values with the same own data but different prototypes compare equal. Without this option, deep equality remains prototype-sensitive.
