Bug: Quotes are formatted in markdown links
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

Links in the format `[link](test.it 'Test title')` become `[link](test.it ‘Test title’)` if `Enable Single Quote Style` is on and Single `Quote Style` set to `‘’`.

## How to Reproduce

Example to reproduce issue with

``` markdown
[link](https://test.it 'Test title')
```

## Expected Behavior

Single or double quotes used in Markdown links to set the link title should be kept `''` and `""`.

Expected output if applicable:

``` markdown
[link](https://test.it 'Test title')
```

## Device

- [x] Desktop
- [ ] Mobile
