Bug: Links with `#` in titles get treated differently
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

A `#` in a hyperlink-title generates the `note` element in the YAML block, structurally different from without a `#` or with `\#`.

## How to Reproduce

Steps to reproduce the behavior:

1. Create a new file
2. Put a hyperlink in the title which has `#` in the text
3. Lint the file

### Examples

``` markdown
# [test #1](github.com/platers/obsidian-linter)
```
``` markdown
# test #2
```
``` markdown
# [test 3](github.com/platers/obsidian-linter)
```
``` markdown
# [test \#4](github.com/platers/obsidian-linter)
```

### Log

[log linter bug diamond.md](https://github.com/platers/obsidian-linter/files/13310164/log.linter.bug.diamond.md)

## Expected Behavior

The `note` YAML should look like usual for links (without syntax or the url)

``` markdown
---
note: "test #"
---
```

## Screenshots

![image](https://github.com/platers/obsidian-linter/assets/61841994/d1fe81ec-8ccd-4849-85d0-df512541e859)

## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

### Additional contract requirements

- The YAML entry that receives the title uses the rule's configured title key (the `titleKey` option), which defaults to `title`. The `note` key shown in the report above reflects the reporter's configured key name; the default key, and the key exercised by the tests, is `title`.
- For a first H1 that is a Markdown link, the value stored under the title key is the link's display text with the Markdown link syntax and URL removed. Concretely:
  - `# [test #1](github.com/platers/obsidian-linter)` produces `title: "test #1"`.
  - `# test #2` produces `title: "test #2"`.
  - `# [test 3](github.com/platers/obsidian-linter)` produces `title: test 3`.
  - `# [test \#4](github.com/platers/obsidian-linter)` produces `title: "test \#4"`.
- A `#` in the link display text must not change the structure of the generated YAML compared to an equivalent title without `#` or with an escaped `\#`.
