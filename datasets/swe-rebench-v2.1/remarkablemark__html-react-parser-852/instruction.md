list value is not preserved while parsing and rendering in UI.
## Expected Behavior
When a list item has a value attribute, the value is not preserved parsing and rendering in UI.
 Ex:  <ol><li value="3">Item-3</li></ol>

## Actual Behavior
It should preserve the list value.
1. Item-3

## Steps to Reproduce
Please check the below link

## Reproducible Demo
https://codesandbox.io/s/loving-violet-2gicem?file=/src/App.js

## Environment
- Version: 3.0.9

### Additional contract requirements

When an HTML list item has a `value` attribute, parsing it must preserve that attribute's value as the resulting React list item's `value` prop. For example, parsing `<ol><li value="3">Item-3</li></ol>` produces a list item whose value prop is `"3"`, allowing the ordered list to honor the item's numbering.
