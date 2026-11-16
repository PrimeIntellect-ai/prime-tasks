Urgency Score for due date changes at midday
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

When I have a task whose due date is today, the due date component of the urgency should be 8.8.

In the Unit tests, when
- **Given** today is `2023-06-26`
- **When** calculating the urgency for this task: `- [ ] 🔽 📅 2023-06-26`
- **Then** the score should be 8.8 for `due` (today) and `0.0` for `Low` priority

This afternoon at 17:45 in the UK, the urgency score is `9.26` which in the tests is the component for `due 1 day ago`.


### Current behaviour

See above

### Steps to reproduce

1. Create a file called `Sample Tests`
1. Paster in the task:

```
- [ ] #task 🔽 📅 2023-06-26
```

2. Set its `due` date to the current day.
3. Paste in this query:

~~~
```tasks
filename includes Sample Tests
group by urgency
show urgency
```
~~~


5. **Note the tasks urgency - it should be 8.8**
6. **Repeat in the afternoon - it should be 8.8**

### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [ ] Linux
- [X] macOS
- [ ] Windows

### Obsidian Version

1.3.5

### Tasks Plugin Version

4.0.0

### Checks

- [ ] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

_No response_
