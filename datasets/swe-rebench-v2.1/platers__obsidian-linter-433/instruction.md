Bug: `YAML Title Alias` rule doesn't respect `Keep alias that matches the filename` setting when aliases section is empty
## Describe the Bug

`YAML Title Alias` rule doesn't respect `Keep alias that matches the filename` setting when aliases section is empty

## How to Reproduce

Consider

**Filename.md**

``` markdown
---
aliases:
---
# Filename
```

Configure `YAML Title Alias` rule setting `Keep alias that matches the filename` = `false`. Run the rule.

## Expected Behavior

`aliases` section has to removed

``` markdown
---
---
# Filename
```

## Actual Behavior

`aliases` section adds `Filename` alias ignoring the setting mentioned.

``` markdown
---
aliases:
  - Filename
---
# Filename
```
