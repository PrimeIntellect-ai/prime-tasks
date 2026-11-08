Bug: no-bare-urls puts closing angle bracket before link's trailing parentheses
- [X] I have verified that I am on the latest version of the Linter

## Describe the Bug

When using the `no-bare-urls` rule on a link definition like `https://en.wikipedia.org/wiki/The_Score_(album)`, the closing angle bracket will get inserted before the ending parentheses instead of getting inserted at the end.

## How to Reproduce

Steps to reproduce the behavior:

Put the following into an obsidian document:

```
[The Score]: https://en.wikipedia.org/wiki/The_Score_(album)
```

Then run the linter. The new format in the document will be:

```
[The Score]: <https://en.wikipedia.org/wiki/The_Score_(album>)
```

## Expected Behavior

Upon running the linter, it is expected that the closing angle bracket is put at the end:

``` markdown
[The Score]: <https://en.wikipedia.org/wiki/The_Score_(album)>
```

## Screenshots

If applicable, add screenshots to help explain your problem.

## Device

- [X] Desktop
- [ ] Mobile

## Additional Context

Add any other context about the problem here.

### Additional contract requirements

- For a link definition whose URL ends in `!`, the linter must include the `!` inside the angle brackets, producing `[This Is Fats Domino!]: <https://en.wikipedia.org/wiki/This_Is_Fats_Domino!>`.
