fill() links to wrong topic
``` r
downlit::highlight("
  library(tidyverse)
  fill()"
)
#> [1] "\n  <span class='kr'><a href='https://rdrr.io/r/base/library.html'>library</a></span><span class='o'>(</span><span class='nv'><a href='https://tidyverse.tidyverse.org'>tidyverse</a></span><span class='o'>)</span>\n  <span class='nf'><a href='https://ggplot2.tidyverse.org/reference/aes_colour_fill_alpha.html'>fill</a></span><span class='o'>(</span><span class='o'>)</span>"
```

<sup>Created on 2022-04-27 by the [reprex package](https://reprex.tidyverse.org) (v2.0.1)</sup>

Should prefer function over floating topic

### Additional contract requirements

- Function calls (in inline code and code blocks) must only link to function
  topics. If a call name matches only a non-function topic (for example a
  dataset), the call must not be linked. Concretely, with `MASS` attached,
  `href_expr_(abbey())` is `NA_character_` and `highlight("abbey()")` produces
  no `<a>` element, even though `abbey` is a topic in `MASS`.
- A help reference such as `?abbey` still links to the (non-function) topic.
