Can't use non-vctrs index types
``` r
library(slider)

x <- structure(1:4, class = "my_integer")
before <- structure(2L, class = "my_integer")

# `c()` doesn't keep class, but `slide_index()` works
c(x, x)
#> [1] 1 2 3 4 1 2 3 4
slide_index(.x = x, .i = x, .f = identity, .before = before)
#> [[1]]
#> [1] 1
#> attr(,"class")
#> [1] "my_integer"
#>
#> [[2]]
#> [1] 1 2
#> attr(,"class")
#> [1] "my_integer"
#>
#> [[3]]
#> [1] 1 2 3
#> attr(,"class")
#> [1] "my_integer"
#>
#> [[4]]
#> [1] 2 3 4
#> attr(,"class")
#> [1] "my_integer"


c.my_integer <- function(...) structure(NextMethod(), class = "my_integer")


# `c()` keeps class, but this means `vec_c()` doesn't work with `name_spec = zap()`
c(x, x)
#> [1] 1 2 3 4 1 2 3 4
#> attr(,"class")
#> [1] "my_integer"
slide_index(.x = x, .i = x, .f = identity, .before = before)
#> Error in `vec_c()`:
#> ! Can't use a name specification with non-vctrs types.
#> vctrs methods must be implemented for class `my_integer`.
#> See <https://vctrs.r-lib.org/articles/s3-vector.html>.

#> Backtrace:
#>     ▆
#>  1. ├─slider::slide_index(.x = x, .i = x, .f = identity, .before = before)
[HIDDEN]
#>  8. └─rlang::abort(message = message, call = call)
```

<sup>Created on 2022-11-09 with [reprex v2.0.2.9000](https://reprex.tidyverse.org)</sup>

### Additional contract requirements

- `slide_index()` should accept non-vctrs S3 types for `.i`, `.before`, and `.after` when they behave like integer positions or lengths. It should produce the same index-defined windows as the corresponding plain integer values.
