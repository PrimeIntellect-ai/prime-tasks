Unicode Variant selectors on some emojis work, while others are parsed incorrectly
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Steps to reproduce

1. Launch an Obsidian vault the latest Tasks 7.13.0 plugin
2. Create a task by manually entering scheduled or due date emojis (hour glass not done, or calendar) using an emoji picker, not the prompt
3. Create a tasks query that uses the emojis, e.g.
```tasks
not done
has scheduled date
sort by description
group by scheduled
```
Result:
Recognized: `- [ ] test ⏳ 2024-11-18`, Not recognized: `- [ ] test ⏳️ 2024-11-18`

### Expected Behavior

Tasks should ignore emoji variants like what is described in https://github.com/obsidian-tasks-group/obsidian-tasks/issues/2273, except on _all_ emojis. Emoji variants should have no effect on its parsing behavior.

### Current behaviour

Currently, Tasks ignores the variant selector on the priority arrows (a previous issue), however it does not ignore it on other emojis like Scheduled. The solution appears to be focused on a specific emoji case, when really it can show up in all emojis. I was initially confused as to why tasks wouldn't show up using a filter, until I played around with different methods of getting the emoji and realized that it must be a variant selector. Sure enough, I was getting `\ufe0f\u23f3` on the hour glass emoji that didn't work, and just `\ufe0f` on the one that did.

### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [X] Linux
- [ ] macOS
- [ ] Windows

### Obsidian Version

1.6.7

### Tasks Plugin Version

7.13.0

### Checks

- [X] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

Implement a solution similar to https://github.com/obsidian-tasks-group/obsidian-tasks/pull/2695, except ignoring variant selectors in _all_ emojis.
