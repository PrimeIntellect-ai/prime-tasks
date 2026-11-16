Bug: `remove-empty-list-markers` not working with non-Latin languages
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

Rule `remove-empty-list-markers` not working if content of the line starts with non-Latin characters

## How to Reproduce

Example to reproduce issue with

``` markdown
- - test content
- - тест content
- - 测试 content
```

Output after ctrl + s:
``` markdown
- test content
- - тест content
- - 测试 content
```

Expected output:

``` markdown
- test content
- тест content
- 测试 content
```

## Device

- [x] Desktop
- [ ] Mobile
