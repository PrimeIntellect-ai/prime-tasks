involves_at_most_one_variable is not exported (rename to isunivariate?)
Terrible name, but if the function is going to exist, it should be accessible.

### Additional contract requirements

Make the predicate available through the public name `isunivariate` for multivariate polynomial elements. It returns true when an element involves at most one distinct variable, including constants, and false when it involves two or more distinct variables. The suggested name `isunivariate` is required; exporting the old name alone does not satisfy this request.
