Bug: `Remove Empty List Markers` rule removes number if it's the only content in the line
## Describe the Bug

`Remove Empty List Markers` rule removes number if it's the only content in the line

## How to Reproduce

Consider note

``` markdown
# World War II

1939
```

And run  `Remove Empty List Markers` rule.

## Expected Behavior

The note is not changed

## Actual Behavior

`1939` is trimmed from the note as it was mistakenly considered to be a list marker, which is weird, because it is not followed by a dot `.`
