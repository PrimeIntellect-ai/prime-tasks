`fail(hint = TRUE)` gives multiple hints in exercises with multiple solutions
`fail(hint = TRUE)` generates a hint for all solutions in exercises with multiple solutions.It should only generate one hint for the solution closest to the user input.

``` r
library(gradethis)

solution_code <- "
# mean ----
mean(1:10)
# median ----
median(1:10)"
```

`fail(hint = TRUE)` generates two hints: one for each solution.

```r
grade_this({
  pass_if_equal()
  fail(hint = TRUE)
})(
  mock_this_exercise("sum(1:10)", !!solution_code)
)
#> <gradethis_graded: [Incorrect]
#>   Incorrect. I expected you to call `mean()` where you called `sum()`.
#>   Try it again. You get better each time. I expected you to call
#>   `median()` where you called `sum()`.
#> >
```

`fail_if_code_feedback()` behaves as expected: it only generates one hint.

```r
grade_this({
  pass_if_equal()
  fail_if_code_feedback()
})(
  mock_this_exercise("sum(1:10)", !!solution_code)
)
#> <gradethis_graded: [Incorrect]
#>   I expected you to call `mean()` where you called `sum()`.
#> >
```

<sup>Created on 2022-04-21 by the [reprex package](https://reprex.tidyverse.org) (v2.0.1)</sup>

### Additional contract requirements

- When a hint is generated for an exercise with multiple solutions, the feedback must contain the phrase `I expected` exactly once.
