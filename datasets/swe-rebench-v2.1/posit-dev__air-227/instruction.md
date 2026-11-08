RHS assignment persistent line breaks introduce extra indentation in pipes
```bash
❯ cat test.R
data <-
  starwars |>
  filter(height > 172) |>
  select(1:3)

❯ air format test.R
❯ cat test.R
data <-
  starwars |>
    filter(height > 172) |>
    select(1:3)

❯ air --version
air 0.3.0
```

As a fan of the persistent line break in this case, I really want all of the expressions in the pipeline to be indented to the same level:

```r
# 😊
data <-
  starwars |>
  filter(height > 172) |>
  select(1:3)

# 😥
data <-
  starwars |>
    filter(height > 172) |>
    select(1:3)
```

### Additional contract requirements

- Apply the same alignment to other chained binary expressions on the right-hand side of a persistently line-broken assignment. For example, format `foo <-\n  1 +\n  2`, `foo <-\n  TRUE ||\n  FALSE`, and `plot <-\n  ggplot() +\n  geom_point()` with each continuation at the same indentation as the first right-hand-side expression.
