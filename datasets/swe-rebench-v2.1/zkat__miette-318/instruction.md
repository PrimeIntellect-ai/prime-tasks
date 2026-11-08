Multiline support for long labels?
Suppose I'm rendering a type error that involves some large/gnarly types. Ideally, I'd like to format/pretty-print those types over multiple lines to make them readable. But afaict this isn't something supported by `miette` at the moment. Any advice? Am I missing something, or are there any plans to support it in future?

### Additional contract requirements

- A diagnostic label may contain newline characters. When a label contains newlines, the graphical report renders each line of the label on its own line, indented so that the label remains readable, rather than emitting the label text verbatim.
