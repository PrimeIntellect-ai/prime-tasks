Feature Request: Add option to offset headings
I would like to ability to offset the headings inside a markdown file I import. I have a Markdown file that can both standalone and be imported into another file.

This could be an option available for every import.

{%
    include-markdown "docs/test.md"
    heading-offset=1
%}

### Additional contract requirements

- If an include uses `heading-offset=true`, leave its Markdown headings unchanged.
