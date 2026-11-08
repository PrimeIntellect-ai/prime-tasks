`press()` varies format of `.grid` values depending on whether `.grid` is a `tbl_df` or `data.frame`
I had expected to be able to access `x` inside of the expression in the same way regardless of whether `.grid` was a `tbl_df` or `data.frame`, but for the former, I'd need to write `x$x` to match the format of the latter:

``` r
library(tibble)

bench::press({print(x); bench::mark()}, .grid = tibble(x = 1))
#> Running with:
#>       x
#> 1     1
#> # A tibble: 1 × 1
#>       x
#>   <dbl>
#> 1     1
#> # A tibble: 0 × 7
#> # ℹ 7 variables: expression <bch:expr>, x <dbl>, min <bch:tm>, median <bch:tm>,
#> #   itr/sec <dbl>, mem_alloc <bch:byt>, gc/sec <dbl>

bench::press({print(x); bench::mark()}, .grid = data.frame(x = 1))
#> Running with:
#>       x
#> 1     1
#> [1] 1
#> # A tibble: 0 × 7
#> # ℹ 7 variables: expression <bch:expr>, x <dbl>, min <bch:tm>, median <bch:tm>,
#> #   itr/sec <dbl>, mem_alloc <bch:byt>, gc/sec <dbl>
```

<sup>Created on 2024-07-02 with [reprex v2.1.0](https://reprex.tidyverse.org)</sup>
