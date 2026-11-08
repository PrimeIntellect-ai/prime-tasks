Bug: Crash when email address added as an alias
## Describe the Bug

Linter crashes if a file contains an email address as an alias

## How to Reproduce

Example to reproduce issue:

``` markdown
---
title: John & Jane Doe
aliases: [John & Jane Doe, email@example.xyz, (123) 456-7890]
cssclass: [table-lines-bright, col-lines, row-lines]
---

# John & Jane Doe

This stuff doesn't really matter.

```

Please make sure to include the rule(s) that cause the issue if applicable. If you are not sure which rule(s) may cause the issue, please attach the `data.json` file located at `<vault>/.obsidian/plugins/obsidian-linter/`.

## Expected Behavior

I expect lint4er not to crash.

## Screenshots

![image](https://user-images.githubusercontent.com/1509989/184920007-00359623-2c95-4370-a70e-bc4677598f65.png)


## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

Attached data.json.txt

This may be a problem with compatibility with meta-edit.

[data.json.txt](https://github.com/platers/obsidian-linter/files/9352373/data.json.txt)

### Additional contract requirements

- When linting the reproduced Markdown document, the output must be byte-for-byte identical to the input.
