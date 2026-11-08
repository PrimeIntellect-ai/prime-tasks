If toggling TO an unknown status, Tasks makes the task invalid, with an empty status character
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

When the custom status settings say that a task's next symbol is a character that is not any of the custom statuses, and the user toggles the task, Tasks should still honour the request for the next symbol.

### Current behaviour

Tasks sets the task's symbol to the empty string, so the task line becomes `- []`, which is not recognised as a task, and is effectively broken.

### Steps to reproduce

### Setup

1. Download and open the build of 84b433bd9dffd72a24f507f826c39a6bff117267
    - by go here https://github.com/obsidian-tasks-group/obsidian-tasks/actions/runs/3868443498
    - downloading the Tasks-Demo zip file
    - expanding it
    - opening the folder in Obsidian
    - trusting the plugins
1. Go to Tasks settings
2. Scroll down to **Custom Status Types**
3. Click **Add New Task Status**
5. Click the Pencil icon
    - Set the boxes to `!`, `Important`, `D`
    - Click the Checkmark to save

### Reproduction

6. Create this new task line in any markdown file:
    `- [!] #task I was important`
7. In Reading mode, click on the checkbox for the new task

### Expected behaviour:
- Task becomes:
    `- [D] #task I was important`

### Actual behaviour:
- Task becomes this - with no character between the square brackets:
    `- [] #task I was important`
and is not longer recognised as a task.




### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [ ] Linux
- [X] macOS
- [ ] Windows

### Obsidian Version

1.1.9

### Tasks Plugin Version

Commit 84b433bd9dffd72a24f507f826c39a6bff117267

### Checks

- [ ] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

[HIDDEN]
The task parsing code already copes with this situation, creating a Status called something like `Unknown (D)` or whatever the unknown symbol was.
