BlockDirective parsing for a new line ")" will give an incorrect output
### Description

```
@Image(
       source: "xx",
       alt: "yy"
)
```

### Checklist

- [X] If possible, I've reproduced the issue using the `main` branch of this package.
- [X] This issue hasn't been addressed in an [existing GitHub issue](https://github.com/apple/swift-docc/issues).

### Expected Behavior

Show the image

### Actual behavior

Show the image with an extra ")"

### Steps To Reproduce

I highly suspect this is a swift-markdown issue

### Swift-DocC Version Information

_No response_

### Swift Compiler Version Information

_No response_
