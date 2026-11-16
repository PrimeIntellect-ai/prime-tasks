`abbr` extension breaks title attribute added using `attr_list`
### Bug description

``` markdown
*[abbr]: Abbreviation Definition

![Image with abbr in title](abbr.png){title="Image with abbr in title"}
```

This renders the attribute code as plain text because the Abbreviation extension modifies the text in the attribute causing it to no longer be a valid attribute list.

### Reproduction

[9.5.18-abbr-attr_list-conflict.zip](https://github.com/Python-Markdown/markdown/files/15077227/9.5.18-abbr-attr_list-conflict.zip)

### Steps to reproduce

1. Enable the `abbr` and `attr_list` extensions
2. Include an abbreviation definition on a page
3. Use the abbreviation in a title attribute for an object using the attr_list syntax
