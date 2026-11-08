Bug report: Created date not automatically added when list contains `- [ ]`
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

Per my settings to "Set created date on every added task" (see screenshot) and the [documentation on created date](https://publish.obsidian.md/tasks/Getting+Started/Dates#Created+date), I expect a created date to be added automatically when I use the [‘Create or edit Task’ Modal](https://publish.obsidian.md/tasks/Getting+Started/Create+or+edit+Task).
![obsidian-tasks-created-date-settings](https://github.com/obsidian-tasks-group/obsidian-tasks/assets/38968656/0e7a8264-5644-4119-94fa-5e78991ee2b3)


### Current behaviour

✅  The expected behavior occurs when I create a new task on a line that does **not** start with `- [ ]`.
❌  However, the expected behavior **fails** to occurs when I create a new task on a line that starts with `- [ ]`. This occurs when I enter a task below another task.

This video shows the expected and unexpected behavior:
https://www.loom.com/share/29fce02dbc884283af2de94ac65fad63

### Steps to reproduce

See video

### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [ ] Linux
- [X] macOS
- [ ] Windows

### Obsidian Version

1.3.5

### Tasks Plugin Version

3.10.0

### Checks

- [ ] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

I believe the issue is that the line already starts with `- [ ]`
