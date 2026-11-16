vec_slice() for bench_expr
``` r
x <- bench:::new_bench_expr(list(quote(1), quote(2)))
x[1]
#> [[1]]
#> [1] 1
#>
#> attr(,"description")
#> [1] ""
vctrs::vec_slice(x, 1)
#> [[1]]
#> [1] 1
#>
#> attr(,"description")
#> [1] "" ""
```

<sup>Created on 2020-06-14 by the [reprex package](https://reprex.tidyverse.org) (v0.3.0)</sup>

CC @lionel-.

### Additional contract requirements

The vctrs proxy of a `bench_expr` object (the value returned by `vctrs::vec_proxy()`) is a data frame with two columns named `x` and `desc`: `x` holds the expressions and `desc` holds the corresponding descriptions. The proxy has one row per expression.
