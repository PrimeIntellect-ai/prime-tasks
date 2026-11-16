Update describe_dict extra stats to return top values for Double columns
- As a user, I wish I could use Woodwork to compute `top_values` for `Double` columns when using `df.ww.describe_dict(extra_stats=True). Currently top values are only returned for `Integer` and `IntegerNullable`.

### Additional contract requirements

- With `extra_stats=True`, a `Double` column whose non-NaN values are all whole numbers should include `top_values`, with values and counts based on their occurrences. A `Double` column containing fractional values should not have populated `top_values`.
- An all-NaN `Double` column should include `top_values` as an empty list.
