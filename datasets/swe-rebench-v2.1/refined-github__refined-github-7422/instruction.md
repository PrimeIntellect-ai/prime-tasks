`sort-conversations-by-update-time` - Prepend sort instead of appending it
### Description

Instead of

```
https://github.com/refined-github/refined-github/issues?q=is%3Aissue+is%3Aopen+sort%3Aupdated-desc
```

it should produce

```
https://github.com/refined-github/refined-github/issues?q=sort%3Aupdated-desc+is%3Aissue+is%3Aopen
```

because the cursor ends up at the end when editing the filter, so the sort filter is more of an annoyance

### Example URLs

https://github.com/refined-github/refined-github/issues
