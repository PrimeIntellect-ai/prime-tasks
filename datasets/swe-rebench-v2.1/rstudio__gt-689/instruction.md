Add option to define table caption and enable cross-referencing
This is an extremely useful package. Thanks! In all my reporting with .Rmd files, I use the `bookdown` file formats `pdf_document2` and `html_document2`, which allow for cross-referencing of tables and figures in text. See here: https://bookdown.org/yihui/bookdown/tables.html

Is there an option available in the `gt` package that allows for tables to have named captions and numbering, which allows for cross-referencing in text using ` \@ref(tab:tab1)`?

### Additional contract requirements

- `gt()` accepts an optional `caption` argument (default `NULL`). When `caption` is non-`NULL`, the returned `gt_tbl` object carries the caption for rendering and cross-referencing.
- The caption accepts plain text, markdown (for example via `md()`), and HTML-compatible inputs (for example `I()`, `htmltools::HTML()`, or `htmltools::tags`).
- When the R session is in knitr rendering mode (`getOption("knitr.in.progress") == TRUE`) and bookdown labeling is active, the caption text is prefixed with a bookdown-style cross-reference label such as `(\#tab:foo)`.
- Rendering a `gt_tbl` that has a caption emits the caption as an HTML `<caption>` element in the table output; a table without a caption emits no `<caption>` element.
