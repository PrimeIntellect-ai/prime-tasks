Add case_sensitive parameter for groupby() filter
`groupby()` filter performs auto sorting under the hood, and it should support specifying case sensitivity for the sort order, the same way `sort()` filter does.


Current `groupby()` implementation always performs case-sensitive sorting under the hood, which makes it inflexible, and behave inconsistently with how the `sort()` filter works (case-insensitive by default). When used in the same template for the same dataset, `groupby()` and `sort()` filters produce different sort order on the same fields.

I think, I would personally prefer to not have any implicit sorting in `groupby()`, and chain it with `sort()` explicitly, but I do understand that auto sorting was, probably, added to `groupby()` for convenience.

Implementing an option to control case sensitivity seems to be pretty straightforward:

[HIDDEN]

If this feature request looks reasonable, I should be able to submit a pull request.

### Additional contract requirements

- The `groupby()` filter must accept a boolean `case_sensitive` option, defaulting to `False`.
- By default, its implicit sorting and grouping must compare values case-insensitively, consistent with the `sort()` filter. Values that differ only by letter case must belong to the same group.
- When `case_sensitive=True`, implicit sorting and grouping must compare values case-sensitively, so values that differ only by letter case can belong to separate groups.
