Bug: `Format Yaml Array` rule breaks nested YAML objects
## Describe the Bug

`Format Yaml Array` rule breaks nested YAML objects

## How to Reproduce

Steps to reproduce the behavior:

``` markdown
---
key1:
  key2: value2
  key3:
    - item1
    - item2
---
```

## Expected Behavior

Not changed

## Actual Behavior

```markdown
key1:
  - item1
  - item2
```markdown
