Hard newline, \\,  fails after relation
A hard newline, `\\,` will properly insert a newline after an ORD atom, as in `M = a \\ b`. But the hard newline is ignored if it follows a relation, as in `M = \\ a`.

LaTeX will insert the newline in either case.

### Additional contract requirements

In the rendered HTML, a hard newline (`\\` or `\newline`) is a top-level element that
carries the `newline` class: a direct child of the `.katex-html` container (a sibling of
the `base` spans), rather than being nested inside a `base` span. This must hold both when
the hard newline follows an ORD atom (e.g. `a \\ b`) and when it follows a relation
(e.g. `M = \\ a`).
