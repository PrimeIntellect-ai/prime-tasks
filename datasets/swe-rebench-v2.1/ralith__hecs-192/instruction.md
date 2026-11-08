"Or"/disjunction query combinator
Currently `Option` allows you to "try" to fetch a fetchable thing; we just came across an issue where we'd like to be able to match on queries which have one fetchable subset *or* another fetchable subset. I think something like an `Or<Q, P>` combinator that implements `Fetch` would be feasible?

### Additional contract requirements

A query can combine two fetchable subsets with an inclusive disjunction: it yields entities for which the left subset, the right subset, or both are available, and does not yield entities for which neither is available.
