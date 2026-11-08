Edit Task modal: switching status to Done or Cancelled changes the existing Done or Cancelled date
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

If a Done date has been set, switching status from Todo to Done should not overwrite an already set Done date. Same thing for Cancelled date & status.

### Current behaviour

If a Done date has been set, switching status from Todo to Done **_overwrites_** an already set Done date. Same thing for Cancelled date & status.

### Steps to reproduce

1. Open Edit Task modal on a task that is not Done status
2. Set Done date to any value other than today's
3. Change status to Done

Same thing for Cancelled date & status.

### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [ ] Linux
- [X] macOS
- [ ] Windows

### Obsidian Version

1.7.1

### Tasks Plugin Version

7.10.0

### Checks

- [ ] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

Setting status to Done or Cancelled should not overwrite an existing Done or Cancelled date but only set it if it was missing.
