Table does not render correct when rowname_col equals groupname_col
Looking at https://github.com/rstudio/gt/blob/ecf27d0a9ecd9e7140bf4e02c4dbc26cf47378ea/R/gt.R#L83, the default rowname_col is "rowname"

For example, if you have a tibble where one of the column names itself is "rowname" and you used it for `groupname_col` argument, then you would notice that either table does not render correctly or you will see an error

Couple of examples below based on https://github.com/rstudio/gt/blob/master/tests/gt-examples/01-html-script/html-11-adding_a_stubhead_label.R and https://github.com/rstudio/gt/blob/master/tests/gt-examples/01-html-script/html-13-adding_footnotes.R

EXAMPLE 1
```r
library(gt)
library(tidyverse)

# Create a table that has a stubhead label
tbl <-
  dplyr::tribble(
    ~groups, ~rowname, ~value_1, ~value_2,
    "A",          1,      361.1,    260.1,
    "A",          2,      184.3,    84.4,
    "A",          3,      342.3,    126.3,
    "A",          4,      234.9,    37.1,
    "B",          1,      190.9,    832.5,
    "B",          2,      743.3,    281.2,
    "B",          3,      252.3,    732.5,
    "B",          4,      344.7,    281.2,
    "C",          1,      197.2,    818.0,
    "C",          2,      284.6,    394.4
  )

# Create a display table
sh_caption_tbl <-
  tbl %>%
  gt(groupname_col = "rowname") %>%
  tab_stubhead(label = "groups")

sh_caption_tbl

```

This would result in following warning message and table with wrong columns and values
<img width="1668" alt="html12-when_rowname_col equals groupname_col" src="https://user-images.githubusercontent.com/5369655/72836141-e8d3f580-3c40-11ea-93d6-9e1f3438b234.png">

EXAMPLE 2

```r
library(gt)
library(tidyverse)

# Create a table with footnotes in various cell types
tbl <-
  dplyr::tribble(
    ~date,        ~rowname,  ~value_1,  ~value_2,
    "2018-02-10", "1",       20.4,      361.1,
    "2018-02-10", "2",       10.9,      743.3,
    "2018-02-10", "3",       34.6,      344.7,
    "2018-02-10", "4",        8.3,      342.3,
    "2018-02-11", "5",       28.3,      234.9,
    "2018-02-11", "6",       75.5,      190.9,
    "2018-02-11", "7",       63.1,        2.3,
    "2018-02-11", "8",       25.8,      184.3,
    "2018-02-11", "9",        5.2,      197.2,
    "2018-02-11", "10",      55.3,      284.6
  )

# Create a display table
footnotes_tbl <-
  gt(data = tbl, groupname_col = "rowname") %>%
  tab_spanner(
    label = "values",
    columns = starts_with("value")
  ) %>%
  tab_footnote(
    footnote = "This is an even smaller number.",
    locations = cells_body(columns = vars(value_1), rows = 9)
  ) %>%
  tab_footnote(
    footnote = "This is a small number.",
    locations = cells_body(columns = vars(value_1), rows = 4)
  ) %>%
  tab_footnote(
    footnote = "First data cell.",
    locations = cells_body(columns = "value_1", rows = 1)
  ) %>%
  tab_footnote(
    footnote = "The first row group",
    locations = cells_row_groups(groups = ends_with("10"))
  ) %>%
  tab_footnote(
    footnote = "Two sets of values",
    locations = cells_column_spanners(spanners = starts_with("val"))
  ) %>%
  tab_footnote(
    footnote = "A stub cell.",
    locations = cells_stub(rows = 1)
  ) %>%
  tab_footnote(
    footnote = md("`value_1` is the first column of values."),
    locations = cells_column_labels(columns = vars(value_1))
  )

footnotes_tbl
```
This gives me following error:

`Error: Can't find column NA in `.data`.`

### Additional contract requirements

- The public constructor is `gt(data, rowname_col = "rowname", groupname_col = dplyr::group_vars(data), ...)` in the `gt` package.
- `gt()` must signal an error when `rowname_col` and `groupname_col` are both non-`NULL` and share any column name.
- `gt()` must signal an error when `rowname_col` names a column that is also used to group `data` (that is, when it appears in `dplyr::group_vars(data)`).
- When the validation passes, `gt()` returns an object of class `gt_tbl`.
