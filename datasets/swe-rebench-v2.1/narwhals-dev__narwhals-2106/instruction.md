[Enh]: Expr.fill_null(value=an_expression)
### We would like to learn about your use case. For example, if this feature is needed  to adopt Narwhals in an open source project, could you please enter the link to it below?


Hi, would it be possible (and wanted) to extend `Expr.fill_null` so that it accepts not just a scalar but also an Expression?

### Please describe the purpose of the new feature or describe the problem to solve.

Personally, I am looking to solve a situation where null values of one column should be replaced by values of another (hopefully non-null) column but in general, the purpose would be to get closer to feature parity with polars (& pandas).

### Suggest a solution if possible.

I would happily try to implement it (for polars and pandas at the least).

### If you have tried alternatives, please describe them below.

_No response_

### Additional information that may help us understand your needs.

_No response_
