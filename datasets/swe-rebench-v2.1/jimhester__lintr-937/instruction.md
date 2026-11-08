... should come 2nd in lint_dir()
Now, if we want to run `lint_dir()` for only a specific linter, we have to somewhat awkwardly pass the default argument to `relative_path`:

```
lintr::lint_dir("/path/to/dir", TRUE, lintr::specific_linter())
```

I think this goes against the tidyverse design principle where `...` is considered "data":

https://design.tidyverse.org/args-data-details.html

Since the next release is a major version bump, I think we can make the change now and try and fix whoever's broken, hopefully few if any people rely on this anyway.
