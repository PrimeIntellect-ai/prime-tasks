Edit Modal ignores edits to cancelled date
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

In Edit Modal setting status to cancelled and setting canceled date to any non today's date and clicking Apply button should save the task with the input cancelled date.

Example:

today is 2024-09-01
I set status to cancelled, the cancelled date is 2024-09-01, I set the cancelled date to any other date -> the task is saved with 2024-09-01 as cancelled date

### Current behaviour

In Edit Modal setting status to cancelled and canceled date to any non today's date and clicking Apply button saves the task with today's cancelled date.

Example:

today is 2024-09-01
I set status to cancelled, the cancelled date is 2024-09-01, I set the cancelled date to 2022-02-02 -> the task is saved with 2022-02-02 as cancelled date

### Steps to reproduce

1. Open Edit Task modal on an existing task `- [ ] #task todo` (Global filter is set to `#task`)
2. Set status to Cancelled (THIS IS THE IMPORTANT STEP, IF OMITTED, EVERYTHING WORKS FINE)
3. Set cancelled date to any date than today's date
4. Click Apply

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

The cancelled date is enabled in the settings.

### Possible solution

_No response_

### Additional contract requirements

When a task is changed to Cancelled in the Edit modal, any cancelled date the user enters after changing the status and before applying the edit must be the date saved on the task. This applies when the entered date differs from today or from the date initially populated when the status changed; the initially populated date must not replace the user's later entry.
