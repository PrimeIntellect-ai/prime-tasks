Edit modal not recognising scheduled date if task line didn't have the Global Filter (when it is set)
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

Task edit modal shall recognise all dates in the line string.

### Current behaviour

Global Filter set to `#task`, the following line is then not treated by Tasks:
![Снимок экрана 2023-06-13 в 13 06 37](https://github.com/obsidian-tasks-group/obsidian-tasks/assets/93825870/0fbac066-28ed-490a-be28-a1e23155a955)

If I place the cursor on that line and run the `Tasks: Create or edit task` command, the edit task modal opens but the scheduled date is in the task description and not in the correct section.
![Снимок экрана 2023-06-13 в 13 06 50](https://github.com/obsidian-tasks-group/obsidian-tasks/assets/93825870/585acf3f-58e7-4be1-9803-27accbf7b460)

After setting a date (2023-06-14 in my example) in the scheduled date field in the edit task modal the scheduled date appears twice:
![Снимок экрана 2023-06-13 в 13 07 15](https://github.com/obsidian-tasks-group/obsidian-tasks/assets/93825870/84875b77-5d3b-4ed8-8db9-4f857ceb773b)

I believe the same thing is valid for all other date.

### Steps to reproduce

1. Set global filter to a word not present in line below.

2. Add the line
```
- [ ] without global filter but with scheduled date ⏳ 2023-06-13
```

3. Open edit task modal

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

_No response_
