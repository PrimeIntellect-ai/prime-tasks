'remove global filter' option breaks display of sub-tags of global filter
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

Global Filter removal in queries shall be done as a word, not as a substring.

For example if
- GF = `#task`
- Global Filter removal option is enabled
- task = `- [ ] #task/something else`

The task shall be rendered as `- [ ] #task/something else`.

The only change in the behaviour shall be regarding the query render - the Global Filter shall not be removed if it is a substring of a bigger word. Even if it not a tag.

### Current behaviour

Now such a task is rendered as `- [ ] /something else`

![Снимок экрана 2023-06-06 в 00 20 49](https://github.com/obsidian-tasks-group/obsidian-tasks/assets/93825870/edad0473-020b-49f1-a656-07877f7e7b8e)


### Steps to reproduce

Source of the test file on the screenshot:
````
- [ ] #task/something else
```tasks
filename includes testfile
```
````

Set Global Filter to #task and enable the Global Filter removal option.

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

I will try to make a PR =)
