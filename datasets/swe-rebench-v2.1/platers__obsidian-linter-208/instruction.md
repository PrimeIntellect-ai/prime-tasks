FR: Capitalize Headings, The words in the Lowercase words list to be Uppercase when it is the first letter
I want to request that for the function of `Capitalize Headings`, the words listed in `the Lowercase Words` better be uppercase when it is the first letter.

For example:
## the Best of the Best

should be
## The Best of the Best

Thanks!

### Additional contract requirements

The `capitalize-headings` rule's `First Letter` style must capitalize the first
alphabetic character (`a`-`z`) in a heading, even when the heading begins with
non-letter characters such as digits or punctuation. For example, with
`Style: 'First Letter'`:

```
# 1. heading attempt
# 1 John
# 1. the Best of the Best
```

should become:

```
# 1. Heading attempt
# 1 John
# 1. The best of the best
```

The rest of the heading is lowercased as before.
