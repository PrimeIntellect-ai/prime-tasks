[Enh]: Support polars.Expr.rank
### We would like to learn about your use case. For example, if this feature is needed  to adopt Narwhals in an open source project, could you please enter the link to it below?


I am abstracting a library for computing teaching metrics so that researchers can use their data processing library of choice. Narwhals seems like a good bet (also shout-out to @mikeckennedy for having you on the podcast!). I can't share the specific repository because it contains internal scripts, but this would be supporting [CourseKata](coursekata.org), a low-cost textbook platform dedicated to continuous improvement based on learning science principles.

### Please describe the purpose of the new feature or describe the problem to solve.

I would like support for the [`polars.Expr.rank`](https://docs.pola.rs/api/python/stable/reference/expressions/api/polars.Expr.rank.html#polars.Expr.rank) method. One example of how it could be used is to count how often an instructor teaches, given some grouping variable (window). In Polars it might look like this:

```python
df.sort("academic_year").with_columns(
  years_taught=pl.col("academic_year")
    .rank(method="dense")
    .over("instructor_id")
)
```

This would window over `instructor_id` and get the rank by `academic_year`. Essentially, we will get a count of how many academic years an instructor has taught in, and because we are using the "dense" ranking, teaching multiple classes in a year counts as a single year taught.

### Suggest a solution if possible.

_No response_

### If you have tried alternatives, please describe them below.

I could probably achieve this by making an intermediate data frame where I filter down `academic_year` using `unique()`, and then make some kind of counter variable based on `instructor_id`, and then `join()` that back to the initial table.

Instead I would rather just go back to using Polars until this feature is supported (if it is on your roadmap!).

### Additional information that may help us understand your needs.

_No response_

### Additional contract requirements

- Provide `Expr.rank(method="average", *, descending=False)`. The `method` choices are `"average"`, `"min"`, `"max"`, `"dense"`, and `"ordinal"`; when omitted, `method` defaults to `"average"`. For tied values, `"average"` assigns the mean rank, `"min"` and `"max"` assign the lowest and highest tied ranks, `"dense"` assigns consecutive ranks to distinct values, and `"ordinal"` assigns separate ranks in encounter order.
- `descending` is a keyword-only boolean. When `True`, rank values from largest to smallest; otherwise, rank from smallest to largest.
