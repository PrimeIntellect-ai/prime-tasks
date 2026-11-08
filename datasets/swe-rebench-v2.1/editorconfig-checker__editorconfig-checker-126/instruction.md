Allow disabling blocks of files
It is extremely common for Markdown files to have link references at the bottom, some of which go well-beyond line maximums.  Markdown syntax does not allow a "comment" to put `<!-- editorconfig-checker-disable-line -->` on these lines.

It would be helpful to be able to disable the checker for blocks of text, as an example (and recommendation):

```md
# My File

...text that is checked by `editorconfig-checker`...

<!-- editorconfig-checker-disable -->

[somelink]:  http://www.some.super.long.url.well.larger.than.the.maximum.line.length/that-I-have-no-control-over.html

<!-- editorconfig-checker-enable -->
```

Similar for other languages, like Python:

```python
import a from b

# editorconfig-checker-disable
some.line("out of compliance")
# editorconfig-checker-enable
```
