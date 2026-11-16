Apply magic line breaks in left assignment operators
I often prefer to have the function call, if/else block, or `%||%` chain on a new line in an assignment:

```r
is_condition_true <-
  if (condition) {
    "yes"
  } else {
    "no"
  }

base_version <-
  version %||%
  b_get(brand, "defaults", "shiny", "theme", "version") %||%
  b_get(brand, "defaults", "bootstrap", "version") %||%
  version_default()
```

Would you consider applying the magic line break logic to the first operator? In other words, the presence of the line break after `<-` would trigger the above formatting.
