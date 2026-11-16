Bug: css color definitions are confused as tags when transferring tags to front matter
## Describe the Bug

I am using linter and setting it up to move tags to the frontmatter.

highlightr plugin uses the syntax

`<mark style="background: #FFB8EBA6;">some text</mark>`
linter confuses the color definition as tags and extracts the color declaration along with all the trailing characters
resulting in

`---
tags:
  - FFB8EBA6;">text</mark>
aliases:
---`

## How to Reproduce
Install linter+highlightr
set up linter to move tags to frontmatter
run linter
