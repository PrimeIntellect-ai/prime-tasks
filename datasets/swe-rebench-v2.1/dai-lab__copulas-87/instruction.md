Make vine copulas sample use num_rows arg.
Currently the sample method on `copulas.multivariate.vine.VineCopulas` doesn't take in consideration the argument num_rows, would be useful to either delete it, or make it work.

### Additional contract requirements

- `VineCopula.sample` accepts a `num_rows` argument (an integer greater than or equal to 1) and returns a `pandas.DataFrame` with `num_rows` rows and one column per variable, whose column names match the columns of the data the model was fitted on, in their original order.
- When the sampled values are integers, the returned `pandas.DataFrame` preserves integer dtype.
