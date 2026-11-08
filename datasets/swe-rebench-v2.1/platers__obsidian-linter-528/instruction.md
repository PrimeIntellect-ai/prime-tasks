Bug: `Empty Line Around Tables` messes up LaTeX with pipe character
## Describe the Bug

`Empty Line Around Tables` messes up LaTeX formulas with pipe (`|`) character

## How to Reproduce

Consider the following note

``` markdown
$|a| + |b|$
```

And enable `Empty Line Around Tables` rule.

## Expected Behavior

Markup unchanged

## Actual Behavior

```markdown
$|a

$|a| + |b|$
$|a
```
