FR: Remove Space Prior to English Punctuation and Full Width Characters
在践行[中文文案排版指北](https://github.com/sparanoid/chinese-copywriting-guidelines)的时候容易多打空格，请问能否用Linter删除以下示例中中文标点前后的空格呢？

Before:

english ， english。

Expected:

english，english。

谢谢

Edit:

Here is the English translation according to Google Translate.

When practicing Chinese copywriting, it is easy to make more spaces. Can I use Linter to delete the spaces before and after the Chinese punctuation in the following example?

Before:

english , english.

Expected:

english, english.

thanks
FR: Allow Removal of Whitespace Before and/or After Characters
## Describe the Bug

**Remove Space around Characters** does not work as described

## How to Reproduce


```
when I type in "This is a fullwidth comma	，  with text after it."
Instead of getting "This is a fullwidth comma，with text after it."
I got "This is a fullwidth comma	， with text after it." (even after lint the file multiple times)
I also found it does not remove space before the character such as "a word , another word"
I have it switched on <img width="792" alt="image" src="https://user-images.githubusercontent.com/7776181/213778443-90b92a0c-a249-443a-9c9b-3119d4a8f113.png">

```

Please make sure to include logs and the rule(s) that cause the issue if applicable. You can include logs by going to the debug tab of the Linter and setting the log level to debug. Then enable the capturing of logs and either lint on save or lint the current file. Then go back to the debug tab and you can grab Linter logs from the last run.

If you are not sure which rule(s) may cause the issue, please attach the `data.json` file located at `<vault>/.obsidian/plugins/obsidian-linter/` or copy the config from the debug tab.

## Expected Behavior

It consistently failed to remove space in front of characters such as "," and ".".

Expected output if applicable:

``` markdown
expected output here
```

## Screenshots

If applicable, add screenshots to help explain your problem.

## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

Add any other context about the problem here.

### Additional contract requirements

- Add a rule exported as the default export named `RemoveSpaceBeforeOrAfterCharacters` in `src/rules/remove-space-before-or-after-characters.ts`.
- The rule exposes `apply(text: string, options): string`, which returns the processed markdown text.
- The rule's options include the string properties `charactersToRemoveSpacesBefore` and `charactersToRemoveSpacesAfter`. Whitespace (spaces and tabs) immediately before any character listed in `charactersToRemoveSpacesBefore` is removed, and whitespace (spaces and tabs) immediately after any character listed in `charactersToRemoveSpacesAfter` is removed.
