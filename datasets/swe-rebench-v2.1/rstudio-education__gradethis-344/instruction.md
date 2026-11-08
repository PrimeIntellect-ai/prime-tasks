`code_feedback()` is too sensitive to argument names passed through `...`
`code_feedback()` finds spurious differences between calls to mapping functions that do and do not use names for arguments passed through `...`.

``` r
library(gradethis)
library(purrr)

fail_if_code_feedback(
  user_code     = "map(list(1:10, 1:20), mean, 0.1, TRUE)",
  solution_code = "map(list(1:10, 1:20), mean, trim = 0.1, na.rm = TRUE)"
)
#> <gradethis_graded: [Incorrect]
#>   Your call to `map()` should include `"trim"` as one of its arguments.
#>   You may have misspelled an argument name, or left out an important
#>   argument.
#> >
```

<sup>Created on 2023-05-01 with [reprex v2.0.2](https://reprex.tidyverse.org)</sup>
