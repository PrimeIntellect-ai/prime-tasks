Lazy Select/Reject
Currently our `Select/Reject` are greedy and generate copies of the input tables. We could create a lazy type for selections similar to what TableOperations.jl does.

### Additional contract requirements

Applying `Select` or `Reject` should expose a lazy result backed by the input table, so changes made to a retained input column remain observable through the result. Selection must retain the requested or matched columns in their established order; rejection must retain the other input columns in input order.
