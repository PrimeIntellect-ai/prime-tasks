Bug: YAML Key Sort Removes Multiline Dictionaries
## Describe the Bug

It looks like, when YAML Key Sort is on and set to sort keys alphabetically, any multiline dictionaries in the metadata will have all their keys deleted. This issue does not occur when key sorting is off, or when the "YAML Sort Order for Other Keys" option is set to "None".

## How to Reproduce

Steps to reproduce the behavior:

1. Make sure "YAML Key Sort" is on in Linter settings, with "YAML Sort Order for Other Keys" set to either Ascending Alphabetical or Descending Alphabetical.
2. Add a multiline dictionary to the YAML front matter (see below for example).
3. Lint file.

Or

Example to reproduce issue with

``` markdown
---
test_key: "Hello"
dictionary:
  abc: "abc"
  def: "def"
tags:
  - Test
---
```

Upon linting, the front matter turns into this:

```markdown
---
dictionary:
tags:
  - Test
test_key: "Hello"
---
```

## Expected Behavior

I expected the keys to be sorted in alphabetical order, without removing the dictionary's keys.

Expected output if applicable:

``` markdown
---
dictionary:
  abc: "abc"
  def: "def"
tags:
  - Test
test_key: "Hello"
---
```

## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

I tried uninstalling and reinstalling the plugin to see if that might fix things, but it didn't seem to have an effect.

It also looks like linting the file while the keys are already in alphabetical order will still delete any dictionary keys. Single-line dictionaries don't seem to be affected.
