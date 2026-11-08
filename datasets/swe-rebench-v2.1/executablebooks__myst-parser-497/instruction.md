Output nested headings as rubric
This should be a quick fix when I'm back at my computer.

When a nested parse is called, e.g. by an admonition directive, `match_title` is set to `False` by default.
(See https://github.com/live-clones/docutils/blob/bd16bdb302f5b24340ddaa69d109d419886bf0ac/docutils/docutils/parsers/rst/states.py#L257)

Then, when a heading underline is encountered in RST, this makes it ignore that heading and just log a warning
(https://github.com/live-clones/docutils/blob/bd16bdb302f5b24340ddaa69d109d419886bf0ac/docutils/docutils/parsers/rst/states.py#L2419)

Currently in myst-parser, an error is correctly logged, but also the heading is still parsed. This can really mess up the resulting AST structure.
Instead of ignoring it though, I think it would be a nice behaviour to still log the warning (which can be suppressed in sphinx) but then output the heading as a rubric, which does not affect the AST structure.

### Additional contract requirements

- The warning message must be exactly `Disallowed nested header found, converting to rubric`.
