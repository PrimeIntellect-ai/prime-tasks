Markdown renderer should infer header level from title format
If you e.g. set `title_format = "#### {name} {version}"`, section headers will have the same header level as the title.

This shouldn’t be the case. Instead sections and section-less categories should be one header level below the title, and categories within sections one more.

Since specifying arbitrarily deep header sections in the `title_format` option, this should of course work by default and not require a template.

Example output:

```markdown
<!-- level(header) is defined by `title_format` ⇒ here level 4 -->
#### Foo 1.2.3

<!-- section-less categories are at level(header) + 1 ⇒ here level 5 -->
##### Features
- Added abc

<!-- sections are at level(header) + 1 too ⇒ here level 5 -->
##### Web

<!-- categories within sections are at level(header) + 2 ⇒ here level 6 -->
###### Bugfixes
- Fixed xyz
```
