Bug: First letter in Title Case not Uppercase when preceded with numbers or special characters
- [x] I have verified that I am on the latest version of the Linter
Linter version 1.25.0

## Describe the Bug

When having a title like this
```
135_  A letter arrived
```
It gets formatted as
```
135 - a Letter Arrived
```

If the letter is in the lowercase words, It will be lowercased even if first letter in the header.

## How to Reproduce

Steps to reproduce the behavior:

1. Make a title similar to mine as the first word is not a letter
2. Set Capitalize Headings to Title Case
3. Ignore Cased Words to false
4. Lowercase Words should have `a` inside for this example.
5. Format the file
6. See error in the first heading

## Resources
[data.json](https://mega.nz/file/EmoEgTaa#VXhUw8w18oBLbm6AQX9ejvzVvzr8pdm9JpKBcKtHxFY)
[logs.txt](https://mega.nz/file/R3RSmJiA#iR95JHnqZ6sf9b_XEUzTP7dqAqaaRcXGoBZ85y3YXA4)

## Expected Behavior

As the linter run, the header
```
135_  A letter arrived
```
should have been
```
135 - A letter arrived
```

## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

As additional context, take note that I am currently using a regex to modify the header to change `_ ` -> ` - ` as:
`^# (\d+)_ (.+)\n` `gm` `# $1 - $2\n`
As I am not an expert in regexes, maybe this can contribute to the bug.
