Escaping input with unclosed, invalid tags returns it with unneeded escaped closing tags appended to end
## To Reproduce

From the Node REPL:
```
> const s = require('sanitize-html')
undefined
> s("here's a string with a <wacky> tag.", {disallowedTagsMode: "escape"})
"here's a string with a &lt;wacky&gt; tag.&lt;/wacky&gt;"
```

## Expected behavior

The offending tag is escaped, but no addition markup is created. For example, given the input `here's a string with a <wacky> tag`, I would expect the output to be: `here's a string with a &lt;wacky&gt; tag`

## Describe the bug

When sanitizing a string with `disallowedTagsMode: "escape"`, extra, unneeded (escaped) closing tags are appended to the end of the string.

## Details

**Version of Node.js:** 15.5.0
**Server Operating System:** Ubuntu 20.04

### Additional contract requirements

- In `recursiveEscape` mode, sanitizing `<test><test><test><test><test>Hello` must return `&lt;test&gt;&lt;test&gt;&lt;test&gt;&lt;test&gt;&lt;test&gt;Hello`.
