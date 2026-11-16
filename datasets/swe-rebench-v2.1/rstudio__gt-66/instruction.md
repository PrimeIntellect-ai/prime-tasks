Fix for `fmt_percent()` when rendering to Latex
Currently, the percentage sign is not escaped for Latex when that is the output mode. Each `fmt_*()` function contains specialized formatter functions for each output mode and [HIDDEN].

### Additional contract requirements

- When `fmt_percent()` renders in LaTeX mode, its percent sign must be escaped so it is rendered as a literal percent character.
