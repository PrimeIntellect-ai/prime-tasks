Not checking reference-style links
### Describe the bug

If you use [reference style links](https://www.markdownguide.org/basic-syntax/#reference-style-links), this check does not fail when the relative path does not exist.

```markdown

[this will be caught](/link-that-does-not-exist)

[but this will not]

[but this will not]: /link-that-does-not-exist
```

### To Reproduce

I created [this repo](https://github.com/dbanty/reproduce-link-checker-reference) from the starlight starter and replaced the content with a single reference that should be caught and is not.

### Expected behavior

Reference-style relative links should be caught the same way as inline links.

### How often does this bug happen?

Every time

### System Info

_No response_

### Additional Context

_No response_
