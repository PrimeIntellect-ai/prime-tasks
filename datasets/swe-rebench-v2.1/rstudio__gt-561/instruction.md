Allow cols_width to be specified relative to each other
Right now, widths in `col_width` must be specified as a number of pixels. I would love to be able to specify column widths relative to each other. For example, I'd love to be able to put in something like
```r
cols_width(gt, vars(double_wide_col) ~ 2, vars(half_wide_col) ~ 0.5, TRUE ~ 1)
```
or even having the `TRUE ~ 1` implied, so it'd be
```r
cols_width(gt, vars(double_wide_col) ~ 2, vars(half_wide_col) ~ 0.5)
```
This would mainly be useful because I don't know the width of my table in px as I'm writing it, but I do know how relatively wide I want my columns.

### Additional contract requirements

- `cols_width(data, ...)` accepts one or more two-sided formulas of the form `vars(col_name) ~ width`. The `width` may be a pixel length (`px()`), a percentage (`pct()`), a bare numeric (treated as a pixel width, so `200` is equivalent to `px(200)`), or an empty string `""` (leaving the column width unset). Columns not named in any formula keep a variable (unset) width.
- Relative column widths are expressed as percentages (for example, `pct(25)` and `pct(50)`), and the specified percentages are preserved in the rendered output.
- `validate_css_lengths(x)` takes a character vector of CSS length strings, ignores empty strings, returns `TRUE` when every non-empty entry is a valid CSS length, and otherwise raises an error.
- In the rendered HTML, a set column width is serialized without spaces around the CSS declaration and with a trailing semicolon, for example `<col style="width:100px;"/>`; an unset column width is serialized as `<col/>`.
