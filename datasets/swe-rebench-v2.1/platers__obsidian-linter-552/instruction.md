Bug: `YAML Title` rule incorrectly considers `#tag` after header as a part of the title
## Describe the Bug

`YAML Title` rule incorrectly considers `#tag` after header as a part of the title

## How to Reproduce

Markup

``` markdown
# title
#tag
```

`YAML Title` rule.

## Expected Behavior

``` markdown
---
title: title
---
# title
#tag
```

## Actual Behavior

``` markdown
---
title: title
#tag
---
# title
#tag
```
