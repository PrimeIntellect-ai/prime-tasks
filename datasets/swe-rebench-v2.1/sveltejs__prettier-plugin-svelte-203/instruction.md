Don't append trailing newline when parsing markdown code blocks
Every other code block formatter (tested with `ts`, `js`, and `html`) leaves the fenced code blocks with no trailing newlines, but this one appends a trailing newline, which is therefore out of place and distracting. It would be great if this could leave 0 trailing newlines in these fenced blocks.

EDIT: namely, remove line 20 of test/printer/samples/markdown.md.
