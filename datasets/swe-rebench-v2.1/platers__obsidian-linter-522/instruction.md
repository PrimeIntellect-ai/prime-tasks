Bug: Move Tags to Yaml not respecting the "Tags to ignore" list
## Describe the Bug
The Move Tags to Yaml option does not respect the "Tags to ignore" list.

## How to Reproduce

### Settings
Turn on Move all tags to Yaml front matter of the document.

Turn "Body tag operation" to "Remove whole tag" option

### Testing
Open markdown file and test:

``` markdown

#tag1
#tag2
#ignored-tag test data
#ignored-tag/nested-tag more tested data

```

Result:
``` markdown
---
tags: tag1 tag2
---

test data
more tested data
```

## Expected Behavior
Expected output:

``` markdown
---
tags: tag1 tag2
---

#ignored-tag test data
#ignored-tag/nested-tag more tested data
```
## Device

- [x] Desktop - macOS Ventura 13.0.1
- [x] Mobile - iOS 16.1.1

Running Linter 1.8.0

## Additional Context

If the "Remove hashtag" option is used instead, it performs as expected. The ignored tags remain hashtagged, and the expected tags that should have the hashtag removed are so.


If you need any more information, please let me know!

Thanks!
