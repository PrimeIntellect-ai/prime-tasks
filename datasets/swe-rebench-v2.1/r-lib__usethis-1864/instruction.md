Error in `compute_name()` when extension is not "R"
Thanks for the great package!

I believe I've encountered a bug.  When a user does `usethis::use_rcpp("code.cpp")`, one gets the error

```
`name` must have extension "cpp", not "cpp"
```

[HIDDEN]

https://github.com/r-lib/usethis/blob/97b2891a838fe0138543a9a93e8b2b7f5cf86677/R/r.R#L81

Here's a reprex demonstrating the problem:

``` r
usethis:::compute_name("code.cpp", ext="cpp")
#> Error:
#> ! `name` must have extension "cpp", not "cpp".
#> Backtrace:
#>     ▆
#>  1. └─usethis:::compute_name("code.cpp", ext = "cpp")
#>  2.   └─cli::cli_abort(...)
#>  3.     └─rlang::abort(...)
```

<sup>Created on 2023-06-17 with [reprex v2.0.2](https://reprex.tidyverse.org)</sup>

I'm about to make a pull request with a proposed fix and an added test demonstrating the problem.

### Additional contract requirements

- When `name` has an extension matching the supplied `ext`, `compute_name()` must accept it and return it unchanged, including when the matching extension is not `R`.
