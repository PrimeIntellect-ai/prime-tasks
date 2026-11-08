`use_codecov_badge()` URL seems incorrect now
i.e. here https://github.com/r-lib/usethis/blob/da18e11fa311ba7034ab58e86bb7b7e0977d1d26/R/coverage.R#L48

It generates a link like this:

```
https://app.codecov.io/gh/tidyverse/tidyr?branch=main
```

but if you go to that, it will still show `master`. It does not seem to know how to handle `?branch=main` and just ignores it, and then shows what it thinks is the default branch, which is `master` unless you've changed it in the codecov settings.

It seems like this might be a more correct link?

```
https://app.codecov.io/gh/tidyverse/tidyr/tree/main
```

That shows `main` for me

### Additional contract requirements

- For `use_codecov_badge("OWNER/REPO")`, the badge must use image URL `https://codecov.io/gh/OWNER/REPO/graph/badge.svg` and link URL `https://codecov.io/gh/OWNER/REPO`.
