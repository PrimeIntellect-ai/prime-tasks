Bug: `Empty Lines Around Code Fences` can cause problems with nested callouts
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

I'm on version 1.23.2 and am experiencing what seems to be a similar issue to #812. However, in my case, the problem is caused by the setting `Empty Line Around Code Fences [x]` as opposed to `Empty Line Around Blockquotes [x]`.

Like the other issue the linter will insert an extra angle bracket between the two child callouts.

## How to Reproduce

While messing around with this I found no tweaks to the blockquote settings had any noticeable changes.
So in order to reproduce this I assume you just need to enable `Empty Line Around Code Fences` and trigger the linter with the following snippet.

````markdown
> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```
````

<details>
<summary>Debug logs</summary>

````
Running linter
Running Format Tags in YAML
format-tags-in-yaml: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

rules before regular rules: 0.09999999403953552 ms
Running Add Blank Line After YAML
add-blank-line-after-yaml: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Dedupe YAML Array Values
dedupe-yaml-array-values: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Format YAML Array
format-yaml-array: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Move Tags to YAML
move-tags-to-yaml: 0.19999998807907104 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Remove YAML Keys
remove-yaml-keys: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Sort YAML Array Values
sort-yaml-array-values: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running File Name Heading
file-name-heading: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Header Increment
header-increment: 0.09999999403953552 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Convert Bullet List Markers
convert-bullet-list-markers: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running No Bare URLs
no-bare-urls: 0.09999999403953552 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Proper Ellipsis
proper-ellipsis: 0.10000002384185791 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Remove Empty List Markers
remove-empty-list-markers: 0.09999999403953552 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Remove Multiple Spaces
remove-multiple-spaces: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Strong Style
strong-style: 0.10000002384185791 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Unordered List Style
unordered-list-style: 0.09999999403953552 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Compact YAML
compact-yaml: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Consecutive blank lines
consecutive-blank-lines: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
>
> > ```
> > another query or basic code-block
> > ```

Running Empty Line Around Blockquotes
empty-line-around-blockquotes: 0.09999999403953552 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
> >
> > ```
> > another query or basic code-block
> > ```

Running Empty Line Around Code Fences
empty-line-around-code-fences: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
> >
> > ```
> > another query or basic code-block
> > ```

Running Empty Line Around Tables
empty-line-around-tables: 0.20000001788139343 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
> >
> > ```
> > another query or basic code-block
> > ```

Running Heading blank lines
heading-blank-lines: 0.09999999403953552 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
> >
> > ```
> > another query or basic code-block
> > ```

Running Line Break at Document End
line-break-at-document-end: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
> >
> > ```
> > another query or basic code-block
> > ```

Running Remove link spacing
remove-link-spacing: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
> >
> > ```
> > another query or basic code-block
> > ```

Running Custom Regex
custom regex rules: 0.09999999403953552 ms
Running Capitalize Headings
capitalize-headings: 0 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
> >
> > ```
> > another query or basic code-block
> > ```

Running Trailing spaces
trailing-spaces: 0.10000002384185791 ms
# Test

> [!multi-column]
>
> > ```
> > some query or basic code-block
> > ```
> >
> > ```
> > another query or basic code-block
> > ```

rules after regular rules: 0.30000001192092896 ms
rules running: 2.9000000059604645 ms
```

rules after regular rules: 0.5 ms
rules running: 5 ms
````

</details>

<details>
<summary>data.json</summary>

```json
{
  "ruleConfigs": {
    "Remove Space around Fullwidth Characters": {
      "Ensures that fullwidth characters are not followed by whitespace (either single spaces or a tab). Note that this may causes issues with markdown format in some cases.": false
    },
    "Space between Chinese and English or numbers": {
      "Ensures that Chinese and English or numbers are separated by a single space. Follows these [guidelines](https://github.com/sparanoid/chinese-copywriting-guidelines)": false
    },
    "escape-yaml-special-characters": {
      "enabled": false,
      "try-to-escape-single-line-arrays": false
    },
    "force-yaml-escape": {
      "enabled": false,
      "force-yaml-escape-keys": ""
    },
    "format-tags-in-yaml": {
      "enabled": true
    },
    "format-yaml-array": {
      "enabled": true,
      "alias-key": true,
      "tag-key": true,
      "default-array-style": "multi-line",
      "default-array-keys": true,
      "force-single-line-array-style": "",
      "force-multi-line-array-style": "tags: "
    },
    "insert-yaml-attributes": {
      "enabled": false,
      "text-to-insert": "aliases: \ntags: "
    },
    "move-tags-to-yaml": {
      "enabled": true,
      "how-to-handle-existing-tags": "Remove whole tag",
      "tags-to-ignore": ""
    },
    "remove-yaml-keys": {
      "enabled": true,
      "yaml-keys-to-remove": "title:"
    },
    "yaml-key-sort": {
      "enabled": false,
      "yaml-key-priority-sort-order": "",
      "priority-keys-at-start-of-yaml": true,
      "yaml-sort-order-for-other-keys": "None"
    },
    "yaml-timestamp": {
      "enabled": false,
      "date-created": true,
      "date-created-key": "created",
      "force-retention-of-create-value": false,
      "date-modified": true,
      "date-modified-key": "modified",
      "format": "YYYY-MM-dd HH:mm:ss"
    },
    "yaml-title": {
      "enabled": false,
      "title-key": "title",
      "mode": "filename"
    },
    "yaml-title-alias": {
      "enabled": false,
      "preserve-existing-alias-section-style": true,
      "keep-alias-that-matches-the-filename": false,
      "use-yaml-key-to-keep-track-of-old-filename-or-heading": true
    },
    "capitalize-headings": {
      "enabled": true,
      "style": "First letter",
      "ignore-case-words": true,
      "ignore-words": "macOS, iOS, iPhone, iPad, JavaScript, TypeScript, AppleScript",
      "lowercase-words": "via, a, an, the, and, or, but, for, nor, so, yet, at, by, in, of, on, to, up, as, is, if, it, for, to, with, without, into, onto, per"
    },
    "file-name-heading": {
      "enabled": true
    },
    "header-increment": {
      "enabled": true,
      "start-at-h2": false
    },
    "footnote-after-punctuation": {
      "enabled": false
    },
    "move-footnotes-to-the-bottom": {
      "enabled": false
    },
    "re-index-footnotes": {
      "enabled": false
    },
    "convert-bullet-list-markers": {
      "enabled": true
    },
    "emphasis-style": {
      "enabled": false,
      "style": "consistent"
    },
    "no-bare-urls": {
      "enabled": true,
      "no-bare-uris": true
    },
    "ordered-list-style": {
      "enabled": false,
      "number-style": "ascending",
      "list-end-style": "."
    },
    "proper-ellipsis": {
      "enabled": true
    },
    "remove-consecutive-list-markers": {
      "enabled": false
    },
    "remove-empty-list-markers": {
      "enabled": true
    },
    "remove-hyphenated-line-breaks": {
      "enabled": false
    },
    "remove-multiple-spaces": {
      "enabled": true
    },
    "strong-style": {
      "enabled": true,
      "style": "consistent"
    },
    "two-spaces-between-lines-with-content": {
      "enabled": false
    },
    "unordered-list-style": {
      "enabled": true,
      "list-style": "-"
    },
    "compact-yaml": {
      "enabled": true,
      "inner-new-lines": true
    },
    "consecutive-blank-lines": {
      "enabled": true
    },
    "convert-spaces-to-tabs": {
      "enabled": false,
      "tabsize": "2"
    },
    "empty-line-around-blockquotes": {
      "enabled": true
    },
    "empty-line-around-code-fences": {
      "enabled": true
    },
    "empty-line-around-math-blocks": {
      "enabled": false
    },
    "empty-line-around-tables": {
      "enabled": true
    },
    "heading-blank-lines": {
      "enabled": true,
      "bottom": true,
      "empty-line-after-yaml": true
    },
    "line-break-at-document-end": {
      "enabled": true
    },
    "move-math-block-indicators-to-their-own-line": {
      "enabled": false
    },
    "paragraph-blank-lines": {
      "enabled": false
    },
    "remove-empty-lines-between-list-markers-and-checklists": {
      "enabled": false
    },
    "remove-link-spacing": {
      "enabled": true
    },
    "space-after-list-markers": {
      "enabled": false
    },
    "trailing-spaces": {
      "enabled": true,
      "twp-space-line-break": true
    },
    "add-blockquote-indentation-on-paste": {
      "enabled": false
    },
    "prevent-double-checklist-indicator-on-paste": {
      "enabled": false
    },
    "prevent-double-list-item-indicator-on-paste": {
      "enabled": false
    },
    "proper-ellipsis-on-paste": {
      "enabled": false
    },
    "remove-hyphens-on-paste": {
      "enabled": false
    },
    "remove-leading-or-trailing-whitespace-on-paste": {
      "enabled": false
    },
    "remove-leftover-footnotes-from-quote-on-paste": {
      "enabled": false
    },
    "remove-multiple-blank-lines-on-paste": {
      "enabled": false
    },
    "add-blank-line-after-yaml": {
      "enabled": true
    },
    "dedupe-yaml-array-values": {
      "enabled": true,
      "dedupe-alias-key": true,
      "dedupe-tag-key": true,
      "dedupe-array-keys": true,
      "ignore-keys": ""
    },
    "sort-yaml-array-values": {
      "enabled": true,
      "sort-alias-key": true,
      "sort-tag-key": true,
      "sort-array-keys": true,
      "ignore-keys": "",
      "sort-order": "Ascending Alphabetical"
    },
    "headings-start-line": {
      "enabled": false
    },
    "remove-trailing-punctuation-in-heading": {
      "enabled": false,
      "punctuation-to-remove": ".,;:!。，；：！"
    },
    "auto-correct-common-misspellings": {
      "enabled": false,
      "ignore-words": ""
    },
    "blockquote-style": {
      "enabled": false,
      "style": "space"
    },
    "default-language-for-code-fences": {
      "enabled": false,
      "default-language": ""
    },
    "quote-style": {
      "enabled": false,
      "single-quote-enabled": true,
      "single-quote-style": "''",
      "double-quote-enabled": true,
      "double-quote-style": "\"\""
    },
    "remove-space-around-characters": {
      "enabled": false,
      "include-fullwidth-forms": true,
      "include-cjk-symbols-and-punctuation": true,
      "include-dashes": true,
      "other-symbols": ""
    },
    "remove-space-before-or-after-characters": {
      "enabled": false,
      "characters-to-remove-space-before": ",!?;:).’”]",
      "characters-to-remove-space-after": "¿¡‘“(["
    },
    "space-between-chinese-japanese-or-korean-and-english-or-numbers": {
      "enabled": false
    }
  },
  "lintOnSave": true,
  "recordLintOnSaveLogs": true,
  "displayChanged": true,
  "lintOnFileChange": true,
  "displayLintOnFileChangeNotice": false,
  "settingsConvertedToConfigKeyValues": true,
  "foldersToIgnore": [
    "99 - Meta/Templates"
  ],
  "linterLocale": "system-default",
  "logLevel": "DEBUG",
  "lintCommands": [],
  "customRegexes": [],
  "commonStyles": {
    "aliasArrayStyle": "single-line",
    "tagArrayStyle": "single string to multi-line",
    "minimumNumberOfDollarSignsToBeAMathBlock": 2,
    "escapeCharacter": "\"",
    "removeUnnecessaryEscapeCharsForMultiLineArrays": true
  }
}
```

</details>

## Expected Behavior

The offending snippet contains code-blocks so it make since why that setting might have some issues,
but I'm not so sure that it should occur in either case when aforementioned setting is enabled or disable.

## Device

- [x] Desktop
- [ ] Mobile

### Additional contract requirements

Linting the reported nested-callout structure must not insert an extra blockquote marker between its child callouts. This must hold whether or not Empty Line Around Code Fences is enabled.
