`call_standardise_formals()` fails when calling `map()` with an index rather than a function
``` r
list <- list(
  c(1, 2),
  c("a", "b")
)

call <- quote(purrr::map(list, 2))

gradethis:::call_standardise_formals(call)
#> Error in `rlang::call2()`:
#> ! Can't create call to non-callable object
#> Backtrace:
#>     ▆
#>  1. ├─gradethis:::call_standardise_formals(call)
#>  2. │ └─gradethis:::call_standardise_passed_arguments(...)
#>  3. │   └─gradethis:::dot_args_standardise(...)
#>  4. │     └─rlang::call2(f_arg, x_arg, !!!dot_args)
#>  5. └─rlang::abort(message = message)
```

<sup>Created on 2023-06-13 with [reprex v2.0.2](https://reprex.tidyverse.org)</sup>

[HIDDEN]

### Additional contract requirements

- `call_standardise_formals()` must standardize a `purrr::map()` call whose `.f` is an index without raising a non-callable error, retaining the supplied index as `.f` in the standardized call.
