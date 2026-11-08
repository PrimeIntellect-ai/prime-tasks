Bug: Sort YAML Array Values rule sorts uppercase values before lowercase ones
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

Sort YAML Array Values claims to sort arrays alphabetically but it actually sorts uppercase values alphabetically first, and then lowercase ones alphabetically.

## How to Reproduce

Steps to reproduce the behavior:

1. Enable Sort YAML Array Values rule and lint a file which has the content below:

Example to reproduce issue with

``` markdown
tags:
  - tag/a
  - tag/B
  - tag/c
  - tag/D
```

Gets linted as

``` markdown
tags:
  - tag/B
  - tag/D
  - tag/a
  - tag/c
```

## Expected Behavior

Sort alphabetically regardless of case.

Expected output if applicable:

(Same as first codeblock above)

``` markdown
tags:
  - tag/a
  - tag/B
  - tag/c
  - tag/D
```

## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

Linter v1.23.1
