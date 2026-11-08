Bug: move-footnotes-to-the-bottom
## Describe the Bug

A clear and concise description of what the bug is.

## How to Reproduce

``` markdown
xxx[^1]

[^1]:[b](http://b.com)

- [a](http://a.com)
```

after save

actual result:

```
xxx[^1]

- [b](http://b.com)

[^1]:[a](http://a.com)
```


## Expected Behavior


``` markdown
xxx[^1]

- [a](http://a.com)

[^1]:[b](http://b.com)
```

## Screenshots

If applicable, add screenshots to help explain your problem.

## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

Add any other context about the problem here.
