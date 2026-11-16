Postponing of tasks only works once
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

The new 'postpone' button should allow postponing a task multiple times.

### Current behaviour

After the first postponement of a task, any subsequent attempts to postpone it give an error.


### Steps to reproduce


1. In a vault with the development version of tasks build - such as version bb479979619d4ca745920dbd65906f39383837f9....
1. Create a file called, for example, `Postpone Tests.md`
2. Paste in this content:

~~~
## Task

- [ ] #task Do stuff 📅 2025-12-02

## Search

```tasks
path includes {{query.file.path}}
```
~~~

4. View in Live Preview or Reading mode

![image](https://github.com/obsidian-tasks-group/obsidian-tasks/assets/4840096/9bdf29fe-dd6e-45a3-a4b1-31507980a712)

5. Click on the Postpone icon at the end of the Task in the query results
6. **Check**:
    - the date should advance to 2025-12-03 in the markdown line
    - the date should advance to 2025-12-03 in the task in the tasks results
    - a success message should be displayed:
        ![image](https://github.com/obsidian-tasks-group/obsidian-tasks/assets/4840096/f2800ddf-d895-4233-940e-81a5fd9f03e2)

7. Click on the Postpone icon at the end of the Task in the query results again

**Expected result:**
    - the date should advance to 2025-12-04 in the markdown line
    - the date should advance to 2025-12-04 in the task in the tasks results
    - and a success notice should be displayed

**Actual result:**
    - the date in the markdown line stays at 2025-12-04
    - the date tasks results advances to 2025-12-04
    - a success message is displayed, and then a failure message:
        ![image](https://github.com/obsidian-tasks-group/obsidian-tasks/assets/4840096/2003756c-af15-40fb-831a-629f24b13c71)



### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [ ] Linux
- [X] macOS
- [ ] Windows

### Obsidian Version

1.5.1

### Tasks Plugin Version

Post 5.2.0 development

### Checks

- [ ] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

_No response_

### Additional contract requirements

- Postponing a task must not modify the original task that was passed in. After the
  postpone operation used by the postpone button (`createPostponedTask()`), the
  original task's date fields must still hold their original values, while the
  returned new task holds the advanced date. This is what allows the same task to be
  located in the file and postponed again on a subsequent click.
