Syntax highlighting of cells should use `julia` syntax
Currently missing kernelspec metadata means it picks `python` when rendered by `quarto`.

### Additional contract requirements

- Generated notebook metadata must include a `kernelspec` object whose `name` starts with `julia`, whose `display_name` starts with `Julia`, and whose `language` is `julia`.
