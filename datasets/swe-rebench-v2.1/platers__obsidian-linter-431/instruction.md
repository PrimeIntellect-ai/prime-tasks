Bug: Date modified value gets duplicated
## Describe the Bug

`date modified` yaml value gets duplicated on saving, but appears as `date data modified`:

```markdown
---
type:
status:
tags:
aliases:
cssclass:
publish: false
date date modified: 2022-09-27 14:30
date created: 2022-09-27 13:39
date modified: 2022-09-27 14:34
---
```

## How to Reproduce

Steps to reproduce the behavior:

1. Download and open the repro vault: [LinterRepro.zip](https://github.com/platers/obsidian-linter/files/9655794/LinterRepro.zip)
2. Open the TestFile
3. Save using Ctrl + S
4. See error
5. Save using Ctrl + S again
6. See a second duplicated line
7. Save using Ctrl + S again
8. see an error message

## Expected Behavior

no duplication

Expected output if applicable:

``` markdown
---
type:
status:
tags:
aliases:
cssclass:
publish: false
date created: 2022-09-27 13:39
date modified: 2022-09-27 14:30
---
```

## Screenshots

![image](https://user-images.githubusercontent.com/5647119/192527911-49dd3930-f559-4bb1-a29e-6bf15985581c.png)

## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

See rules in repro vault. Does not happen with default rules.

### Additional contract requirements

- The `Remove YAML Keys` rule must match whole YAML keys only. A key listed in `yamlKeysToRemove` must not match a longer key that merely contains it as a substring: removing `created` must leave `date created` and `date modified` intact instead of corrupting the frontmatter into `date date modified`.
