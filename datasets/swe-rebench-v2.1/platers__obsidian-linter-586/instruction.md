Bug: Move Tags to Yaml incorrectly identifies titles with # in the hyperlink as labels
## Describe the Bug

`Move Tags to Yaml` incorrectly identifies titles with # in the hyperlink as labels

## How to Reproduce

Paste the following text into Obsidian

``` markdown
Hyperlink example:
[Travis Linux builds failing: can't find FFTW · Issue #152 · SHTOOLS/SHTOOLS · GitHub](https://github.com/SHTOOLS/SHTOOLS/issues/152)
```

with rules setting like this:

![1673245016572](https://user-images.githubusercontent.com/30110832/211250218-8c11bbd3-6e12-499a-a22c-2f0ecc8e22eb.png)

After Linter, the tags field in the yaml section will have an additional tag named 152, due to the text `Issue #152` in the link title being recognized as a note tag

```yaml
---
tags: [152]
---
```

DEBUG logs as follows:
```
Running linter
Running Move Tags to Yaml
Running YAML Title
Running Headings Start Line
Running Remove Trailing Punctuation in Heading
Running Remove Consecutive List Markers
Running Remove Empty List Markers
Running Remove Hyphenated Line Breaks
Running Remove Multiple Spaces
Running Empty Line Around Blockquotes
Running Empty Line Around Code Fences
Running Empty Line Around Math Blocks
Running Empty Line Around Tables
Running Heading blank lines
Running Remove link spacing
Running Space between Chinese Japanese or Korean and English or numbers
Running Trailing spaces
Running Custom Regex
Running YAML Timestamp
Running Custom Lint Commands
```

## Expected Behavior

Ignore `#` content in the note text (images, web links, etc.) as these are not tagging the note

## Device

- [x] Desktop
- [ ] Mobile
