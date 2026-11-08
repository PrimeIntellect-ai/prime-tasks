Bug: The formatting result is incorrect when the image has a description and size attributes.
## Describe the Bug

The formatting result is incorrect when the image has a description and size attributes.

## How to Reproduce

``` markdown
![[流浪地球-1.webp|image title|600]]
```
after formatting
```markdown
![[流浪地球 -1.webp|image title|600]]
```
added  a space between CJK character "流浪地球" and  "-1.webp"
but no such this file.

## Expected Behavior

Expected output if applicable:

do not add space between Chinese and numbers
``` markdown
![[流浪地球-1.webp|image title|600]]
```

## Screenshots

https://user-images.githubusercontent.com/4202032/230772115-00052d28-79c6-463c-96c1-8477951262c5.mp4


## Additional Context

The related issue: https://github.com/platers/obsidian-linter/issues/583
