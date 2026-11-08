Bug: Indentation Removed from Lists Nested in Block Quote or Callout
## Describe the Bug

Linter destroys legitimately formatted multi-level unordered lists within quote blocks & callouts

## How to Reproduce

1. Create an unordered list with multiple indentation levels.
2. Add '>' to the beginning of the lines to create a quote block or callout
3. Run linter.
4. Observe that the whitespace between '>' and '-' used to create the multiple levels of the list has been collapsed, and the list is no longer multi-level.

## Expected Behavior

Linter should ignore spaces between a '>' at the beginning of the line and '-' regardless of the rules selected.

## Screenshots

![2022-07-15_13-36-56](https://user-images.githubusercontent.com/1509989/179279370-0077d80a-0efd-4b71-84e3-bf3c74b84654.gif)

## Device

- [x] Desktop
- [ ] Mobile

[data.json.txt](https://github.com/platers/obsidian-linter/files/9122892/data.json.txt)
