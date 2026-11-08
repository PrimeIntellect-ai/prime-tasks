Tables in tight list items don't render
**Version(s) affected**: 1.5.7

**Description**

table syntax included after plain text in a list item is rendered as plain text instead of a table. this differs from cmark-gfm, where the text and table are rendered as children of the list item. this only happens when there are no empty lines between the text and table (if there are, it renders as a paragraph and table correctly)

it looks like an issue specific to tables because other block-level elements are working fine here, I tested blockquotes and code blocks

**How to reproduce**

[compare on babelmark](https://babelmark.github.io/?text=-+list+item%0A++%7C+head+%7C%0A++%7C+%3A--+%7C%0A++%7C+body+%7C) between league/commonmark GFM and GitHub Flavored Markdown
