`Overflow` feature
Feature inspired by [poolboy](https://github.com/devinus/poolboy).

`Poolex` should be able to create a configurable number of workers in excess of a constant value (if the load has increased and there are no free workers left in the pool).

### Additional contract requirements

The excess-worker limit is configured at pool startup with the `:max_overflow` option. If omitted, the limit is `0`.
