Reporting is a little hard to read
### Overview

Looking at the CLI output with a fresh set of eyes, I'm finding it hard to distinguish between groups - even with different colors on some of them. Also, some groups indent sub-messages with `\t`s, and others with `  `s. Harumph.

#### Actual Behavior

![Screenshot of groups with no spacing between them](https://user-images.githubusercontent.com/3335181/71420286-699fd180-2642-11ea-9265-9681e68b7145.png)

#### Expected Behavior

Let's space them out a bit more! I'd prefer this:

![Screenshot of standardized spacing between groups](https://user-images.githubusercontent.com/3335181/71420272-58ef5b80-2642-11ea-9933-4cdf367969e8.png)

### Additional contract requirements

The reporting output must group and space its sections consistently:

- In the CLI's error output, each complaint line is indented by two spaces.
- In the CLI's error output, the error-count line reads "N error(s) running tslint-to-eslint:" with no extra spaces.
- In the CLI's error output, each stack trace is indented by two spaces.
- Missing-conversion messages are preceded by a blank line, use the ❓ emoji, and place "See generated log file" on a new line indented by two spaces.
- Rule-behaviour notices are preceded by a blank line and introduced by a heading line beginning with "❗ " followed by the count and " ESLint"; each rule line is indented by two spaces in the form "  * rule:" and its notices are indented by four spaces in the form "    - notice".
- Package-missing output lists each required package indented by two spaces instead of a tab.
- Missing editor-setting warnings are preceded by a blank line, use the ❓ emoji, and include "See generated log file."
- Editor-setting error summaries use the ❌ emoji.
- The "Check … for details." hint is indented by two spaces.


- Use these exact missing-conversion summary forms: “❓ 1 rule does not yet have an ESLint equivalent ❓”, “❓ 2 rules do not yet have ESLint equivalents ❓”, “❓ 1 editor setting does not yet have an ESLint equivalent ❓”, and “❓ 2 editor settings do not yet have ESLint equivalents ❓”. For two missing rules, the indented line reads exactly “  See generated log file; defaulting to eslint-plugin-tslint for these rules.”
