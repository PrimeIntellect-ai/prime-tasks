date function fails for null values when format is given.
### What happened?

I try to have some timetracking in my obsidian. Therefore, I create notes with frontmatter tags "start" and "end" and a link back to my daily note.
In said daily note I have a dataview that is supposed to show all "timetracking entries" (eg notes).
I then tried to make dataview automatically calculate the duration of each task, and my query resulted in an error:
`No implementation of 'date' found for arguments: null, string`
I found out why this happens - because as long as a task is running, the "end" frontmatter tag is not set. I simplified the problem to the provided DQL.
The line `  , date(end, "yyyy")` breaks the query,
![image](https://github.com/blacksmithgu/obsidian-dataview/assets/142982206/61f20956-a089-46cc-9ee3-6ee2be4cc802)
the line `  , date(end)` is fine
![image](https://github.com/blacksmithgu/obsidian-dataview/assets/142982206/a22ac252-2174-4149-a3b4-eb624ef24484)


So, apparently, `date(null)` is fine, `date(null, "some format")` is not.

### DQL

```dataview
TABLE WITHOUT id
  link(file.name, task) as "Task"
  , end
  , date(end)
  , date(end, "yyyy")
FROM [[2024-03-01]]
SORT file.name
```

### JS

_No response_

### Dataview Version

0.5.64

### Obsidian Version

1.5.8

### OS

Linux
