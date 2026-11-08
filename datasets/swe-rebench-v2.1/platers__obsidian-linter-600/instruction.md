Bug: Erroneous Table Match Causes Content Duplication when Table Match Is Not Start of Line
## Describe the Bug

WHEN SAVE AND LINT, DUPLICATES SOME LINE AUTOMATICLY.

## How to Reproduce

Steps to reproduce the behavior:

1. Create a new note
2. Paste `magneto - | maɡˈnedō |` to the editor
3. Save it
4. Will see the content becomes to:
   ```
   magneto

   magneto - | maɡˈnedō |

   magneto
   ```
5. If placed `magneto - | maɡˈnedō |` into code block, will not generate duplicated lines.

Please make sure to include logs and the rule(s) that cause the issue if applicable. You can include logs by going to the debug tab of the Linter and setting the log level to debug. Then enable the capturing of logs and either lint on save or lint the current file. Then go back to the debug tab and you can grab Linter logs from the last run.

If you are not sure which rule(s) may cause the issue, please attach the `data.json` file located at `<vault>/.obsidian/plugins/obsidian-linter/` or copy the config from the debug tab.

[data.json.zip](https://github.com/platers/obsidian-linter/files/10365663/data.json.zip)

## Expected Behavior

DO NOT DUPLICATE THE CONTENT.

## Screenshots

![obsidian-linter-bug](https://user-images.githubusercontent.com/275233/211135422-b9c83069-1836-4b2f-85a5-61406005477f.gif)

## Device

- [x] Desktop

## Additional Context

macOS 13.1
Obsidian: 1.1.9
Obsidian Linter: 1.10.1
