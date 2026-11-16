It's easy to accidentally mutate child in `Sanitize`
A `ChildReconciler`'s `Sanitize`'s purpose is to produce a log-able `interface{}` without compromising confidential data.

However, `Sanitize`'s type is `func(child *Child) interface{}`. That makes it easy to accidentally mutate the child and break reconciliation.

[HIDDEN] However, I am not sure if that will regress performance.

Alternatively, `Sanitize`'s doc could mention the risk to the traveller.

### Additional contract requirements

- Mutations made by `Sanitize` must not alter the child used by reconciliation.
