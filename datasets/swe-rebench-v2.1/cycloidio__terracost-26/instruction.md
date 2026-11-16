estimation: Return a list of errors instead of failing the entire process
## Abstract

Failing the entire cost estimation process because of a single failure in retrieving the correct product/price is not the best UX. The failure should be recorded and an error returned, however, all the successful estimates should be returned as well.

## Implementation details

For example, by adding a new field to the `cost.State` struct that holds the failed resources and the error of each, e.g. in a `map[string]error`. As well as a method on `cost.Plan` that can be used to retrieve all the failed resources.

## Suggestions/ideas

This is similar in concept to #12 and could probably be accomplished together.

### Additional contract requirements

- `cost.NewState` returns a `*cost.State` with a nil error even when individual product or price lookups fail; each failure is recorded on the corresponding `cost.Component`'s `Error` field instead of aborting the whole estimation.
- When a product lookup yields no matching product, the recorded component error is `cost.ErrProductNotFound`; when a price lookup yields no matching price, the recorded component error is `cost.ErrPriceNotFound`.
- Components whose lookups succeed are still populated with their computed cost, even when other components in the same state failed.
- A `cost.Plan` must retain failed resources in its resource differences and expose the lookup errors for their components.
