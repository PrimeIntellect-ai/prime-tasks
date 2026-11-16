Bug: replace doesn't replaceAll
### What happened?

I'm currently debugging through `dv.sectionLink` and came across this:
![image](https://github.com/blacksmithgu/obsidian-dataview/assets/559564/aa7a3283-6c53-4ff7-9d0e-f244831af80e)

if you run `"|||".replace("|", "\\|")` in your console, you will get this: `\|||`
to get the correct output, [HIDDEN]

I'll create a pull request for this immediately.

### DQL

_No response_

### JS

_No response_

### Dataview Version

0.5.64

### Obsidian Version

v1.5.8

### OS

Windows

### Additional contract requirements

- Section links must escape every `|` character in the link target, not only the first one. For example, a link to the block target `a|b|c` in note `Note` must render as `Note#^a\|b\|c`, so the pipes do not break the link.
- The same applies to every `|` character in the note path that a link points to.
