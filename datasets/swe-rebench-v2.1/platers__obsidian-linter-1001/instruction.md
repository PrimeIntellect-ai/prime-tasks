Bug: Page links break table formatting
- [x] I have verified that I am on the latest version of the Linter (1.22.0)

## Describe the Bug

A table in my document contains links to other pages within its cells.

However, the linter treats these tables as paragraphs and applies the wrong set of rules, specifically the `paragraph-blank-lines` rule.  Disabling this rule is a workaround for the issue.

## How to Reproduce

Example markup:

``` markdown
| 1 | 2 |
| --- | --- |
| 3 | 4 |

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 3 | 4 |
```

## Expected Behavior

The document should remain the same.

## Actual Behaviour

Instead, extra empty lines are added.

```markdown
| 1 | 2 |
| --- | --- |
| 3 | 4 |

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |

| --- | --- |

| 3 | 4 |
```

<img width="780" alt="Screenshot 2024-01-25 at 21 15 25" src="https://github.com/platers/obsidian-linter/assets/208751/01737442-fb15-49e9-8c60-f836174d2eb1">

## Device

- [x] Desktop
- [ ] Mobile (not tested)

## Additional Context

### Logs

<details><summary>Details</summary>
<p>

```
Running linter
rules before regular rules: 0 ms
Running Add Blank Line After YAML
add-blank-line-after-yaml: 0.10000002384185791 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Header Increment
header-increment: 2.100000023841858 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Remove Trailing Punctuation in Heading
remove-trailing-punctuation-in-heading: 0.10000002384185791 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Emphasis Style
emphasis-style: 0.7999999523162842 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Remove Empty List Markers
remove-empty-list-markers: 0.20000004768371582 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Strong Style
strong-style: 0 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Unordered List Style
unordered-list-style: 0.10000002384185791 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Consecutive blank lines
consecutive-blank-lines: 0.10000002384185791 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Convert Spaces to Tabs
convert-spaces-to-tabs: 0.10000002384185791 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Empty Line Around Blockquotes
empty-line-around-blockquotes: 0 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Empty Line Around Code Fences
empty-line-around-code-fences: 0 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Empty Line Around Math Blocks
empty-line-around-math-blocks: 0 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Empty Line Around Tables
empty-line-around-tables: 0.30000007152557373 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Heading blank lines
heading-blank-lines: 0.2999999523162842 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Line Break at Document End
line-break-at-document-end: 0 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |
| --- | --- |
| 1 | 2 |

Running Paragraph blank lines
paragraph-blank-lines: 0.10000002384185791 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |

| --- | --- |

| 1 | 2 |

Running Remove Empty Lines Between List Markers and Checklists
remove-empty-lines-between-list-markers-and-checklists: 2.0999999046325684 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |

| --- | --- |

| 1 | 2 |

Running Space after list markers
space-after-list-markers: 0.20000004768371582 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |

| --- | --- |

| 1 | 2 |

Running Custom Regex
custom regex rules: 0.10000002384185791 ms
Running Blockquote Style
blockquote-style: 0.10000002384185791 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |

| --- | --- |

| 1 | 2 |

Running YAML Timestamp
yaml-timestamp: 0.40000009536743164 ms
---
day: "[[2024-01-25]]"
---

| [[2024-01-25\|Thursday]] | [[2024-01-26\|Friday]] |

| --- | --- |

| 1 | 2 |

rules after regular rules: 0.6000000238418579 ms
rules running: 8.100000023841858 ms
```

</p>
</details>

### Config

<details><summary>Details</summary>
<p>

```json
{
  "ruleConfigs": {
    "escape-yaml-special-characters": {
      "enabled": false,
      "try-to-escape-single-line-arrays": false
    },
    "force-yaml-escape": {
      "enabled": false,
      "force-yaml-escape-keys": ""
    },
    "format-tags-in-yaml": {
      "enabled": false
    },
    "format-yaml-array": {
      "enabled": false,
      "alias-key": true,
      "tag-key": true,
      "default-array-style": "single-line",
      "default-array-keys": true,
      "force-single-line-array-style": "",
      "force-multi-line-array-style": ""
    },
    "insert-yaml-attributes": {
      "enabled": false,
      "text-to-insert": "aliases: \ntags: "
    },
    "move-tags-to-yaml": {
      "enabled": false,
      "how-to-handle-existing-tags": "Nothing",
      "tags-to-ignore": ""
    },
    "remove-yaml-keys": {
      "enabled": false,
      "yaml-keys-to-remove": ""
    },
    "yaml-key-sort": {
      "enabled": false,
      "yaml-key-priority-sort-order": "type\nday\nday_of_week\narea\nproject\nperson\nsoftware\nhardware\ncountry\ncity\npoi\ncompany",
      "priority-keys-at-start-of-yaml": true,
      "yaml-sort-order-for-other-keys": "None"
    },
    "yaml-timestamp": {
      "enabled": true,
      "date-created": true,
      "date-created-key": "day",
      "force-retention-of-create-value": true,
      "date-modified": false,
      "date-modified-key": "day_updated",
      "format": "\"\\[\\[YYYY-MM-DD\\]\\]\""
    },
    "yaml-title": {
      "enabled": false,
      "title-key": "title"
    },
    "yaml-title-alias": {
      "enabled": false,
      "preserve-existing-alias-section-style": true,
      "keep-alias-that-matches-the-filename": false,
      "use-yaml-key-to-keep-track-of-old-filename-or-heading": true
    },
    "capitalize-headings": {
      "enabled": false,
      "style": "Title Case",
      "ignore-case-words": true,
      "ignore-words": "macOS, iOS, iPhone, iPad, JavaScript, TypeScript, AppleScript, I",
      "lowercase-words": "a, an, the, aboard, about, abt., above, abreast, absent, across, after, against, along, aloft, alongside, amid, amidst, mid, midst, among, amongst, anti, apropos, around, round, as, aslant, astride, at, atop, ontop, bar, barring, before, B4, behind, below, beneath, neath, beside, besides, between, 'tween, beyond, but, by, chez, circa, c., ca., come, concerning, contra, counting, cum, despite, spite, down, during, effective, ere, except, excepting, excluding, failing, following, for, from, in, including, inside, into, less, like, minus, modulo, mod, near, nearer, nearest, next, notwithstanding, of, o', off, offshore, on, onto, opposite, out, outside, over, o'er, pace, past, pending, per, plus, post, pre, pro, qua, re, regarding, respecting, sans, save, saving, short, since, sub, than, through, thru, throughout, thruout, till, times, to, t', touching, toward, towards, under, underneath, unlike, until, unto, up, upon, versus, vs., v., via, vice, vis-à-vis, wanting, with, w/, w., c̄, within, w/i, without, 'thout, w/o, abroad, adrift, aft, afterward, afterwards, ahead, apart, ashore, aside, away, back, backward, backwards, beforehand, downhill, downstage, downstairs, downstream, downward, downwards, downwind, east, eastward, eastwards, forth, forward, forwards, heavenward, heavenwards, hence, henceforth, here, hereby, herein, hereof, hereto, herewith, home, homeward, homewards, indoors, inward, inwards, leftward, leftwards, north, northeast, northward, northwards, northwest, now, onward, onwards, outdoors, outward, outwards, overboard, overhead, overland, overseas, rightward, rightwards, seaward, seawards, skywards, skyward, south, southeast, southwards, southward, southwest, then, thence, thenceforth, there, thereby, therein, thereof, thereto, therewith, together, underfoot, underground, uphill, upstage, upstairs, upstream, upward, upwards, upwind, west, westward, westwards, when, whence, where, whereby, wherein, whereto, wherewith, although, because, considering, given, granted, if, lest, once, provided, providing, seeing, so, supposing, though, unless, whenever, whereas, wherever, while, whilst, ago, according to, as regards, counter to, instead of, owing to, pertaining to, at the behest of, at the expense of, at the hands of, at risk of, at the risk of, at variance with, by dint of, by means of, by virtue of, by way of, for the sake of, for sake of, for lack of, for want of, from want of, in accordance with, in addition to, in case of, in charge of, in compliance with, in conformity with, in contact with, in exchange for, in favor of, in front of, in lieu of, in light of, in the light of, in line with, in place of, in point of, in quest of, in relation to, in regard to, with regard to, in respect to, with respect to, in return for, in search of, in step with, in touch with, in terms of, in the name of, in view of, on account of, on behalf of, on grounds of, on the grounds of, on the part of, on top of, with a view to, with the exception of, à la, a la, as soon as, as well as, close to, due to, far from, in case, other than, prior to, pursuant to, regardless of, subsequent to, as long as, as much as, as far as, by the time, in as much as, inasmuch, in order to, in order that, even, provide that, if only, whether, whose, whoever, why, how, or not, whatever, what, both, and, or, not only, but also, either, neither, nor, just, rather, no sooner, such, that, yet, is, it"
    },
    "file-name-heading": {
      "enabled": false
    },
    "header-increment": {
      "enabled": true,
      "start-at-h2": true
    },
    "headings-start-line": {
      "enabled": false
    },
    "remove-trailing-punctuation-in-heading": {
      "enabled": true,
      "punctuation-to-remove": "."
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
    "auto-correct-common-misspellings": {
      "enabled": false,
      "ignore-words": ""
    },
    "convert-bullet-list-markers": {
      "enabled": false
    },
    "emphasis-style": {
      "enabled": true,
      "style": "underscore"
    },
    "no-bare-urls": {
      "enabled": false
    },
    "ordered-list-style": {
      "enabled": false,
      "number-style": "ascending",
      "list-end-style": "."
    },
    "proper-ellipsis": {
      "enabled": false
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
      "enabled": false
    },
    "strong-style": {
      "enabled": true,
      "style": "asterisk"
    },
    "two-spaces-between-lines-with-content": {
      "enabled": false
    },
    "unordered-list-style": {
      "enabled": true,
      "list-style": "-"
    },
    "compact-yaml": {
      "enabled": false,
      "inner-new-lines": false
    },
    "consecutive-blank-lines": {
      "enabled": true
    },
    "convert-spaces-to-tabs": {
      "enabled": true,
      "tabsize": "4"
    },
    "empty-line-around-blockquotes": {
      "enabled": true
    },
    "empty-line-around-code-fences": {
      "enabled": true
    },
    "empty-line-around-math-blocks": {
      "enabled": true
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
      "enabled": true
    },
    "remove-empty-lines-between-list-markers-and-checklists": {
      "enabled": true
    },
    "remove-link-spacing": {
      "enabled": false
    },
    "remove-space-around-characters": {
      "enabled": false,
      "include-fullwidth-forms": true,
      "include-cjk-symbols-and-punctuation": true,
      "include-dashes": true,
      "other-symbols": ""
    },
    "space-after-list-markers": {
      "enabled": true
    },
    "space-between-chinese-japanese-or-korean-and-english-or-numbers": {
      "enabled": false
    },
    "trailing-spaces": {
      "enabled": false,
      "twp-space-line-break": false
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
    "blockquote-style": {
      "enabled": true,
      "style": "space"
    },
    "quote-style": {
      "enabled": false,
      "single-quote-enabled": true,
      "single-quote-style": "''",
      "double-quote-enabled": true,
      "double-quote-style": "\"\""
    },
    "remove-space-before-or-after-characters": {
      "enabled": false,
      "characters-to-remove-space-before": ",!?;:).’”]",
      "characters-to-remove-space-after": "¿¡‘“(["
    },
    "add-blank-line-after-yaml": {
      "enabled": true
    },
    "default-language-for-code-fences": {
      "enabled": false,
      "default-language": ""
    }
  },
  "lintOnSave": true,
  "recordLintOnSaveLogs": true,
  "displayChanged": true,
  "lintOnFileChange": true,
  "displayLintOnFileChangeNotice": true,
  "settingsConvertedToConfigKeyValues": true,
  "foldersToIgnore": [
    "Resources/Софт/Obsidian/Templates"
  ],
  "linterLocale": "system-default",
  "logLevel": "DEBUG",
  "lintCommands": [],
  "customRegexes": [],
  "commonStyles": {
    "aliasArrayStyle": "single-line",
    "tagArrayStyle": "single-line",
    "minimumNumberOfDollarSignsToBeAMathBlock": 2,
    "escapeCharacter": "\"",
    "removeUnnecessaryEscapeCharsForMultiLineArrays": true
  }
}
```

</p>
</details>
