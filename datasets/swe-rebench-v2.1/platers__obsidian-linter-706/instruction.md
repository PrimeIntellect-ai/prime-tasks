Bug: Unexpected blank line.
``` markdown
### 調査企画書 BEFORE

**【状況理解（背景）】**
  - 事業上どのような課題があるのか
  - 調査結果からどのようなアクションをしたいのか
**【問い（目的）】**
  - 何を明らかにするのか
**【対象】**
  - どのような人を対象にするか
```

``` markdown
### 調査企画書 AFTER

**【状況理解（背景）】**

  - 事業上どのような課題があるのか
  - 調査結果からどのようなアクションをしたいのか
**【問い（目的）】**
  - 何を明らかにするのか
**【対象】**
  - どのような人を対象にするか
```

A blank line will be inserted after row 3 (【状況理解（背景）】).
Prettier won't add it.

And if you need the settings, please let me know which file contains it.

### Additional contract requirements

The blank line after the bold Japanese label in the example above is the expected
output of the paragraph blank lines rule. The defect to fix is that a bare empty
list indicator followed by a blank line is incorrectly identified as a Markdown
table, which makes the paragraph blank lines rule insert extra blank lines around
it.

A bare empty list indicator is a list item line whose content is only the list
marker: `- ` (a hyphen followed by a space) or `- [ ] ` (an unchecked task list
marker). Such a line, when followed by a blank line, must not be identified as a
Markdown table. Consequently:

- `getAllTablesInText` must report zero tables for text such as
  `## Attendees\n\n- \n\n## Agenda`.
- The paragraph blank lines rule must leave text such as
  `## Attendees\n\n- \n\n## Agenda` unchanged, adding no blank lines around the
  bare empty list indicator. This must also hold when several such empty list
  indicators appear in different sections.
