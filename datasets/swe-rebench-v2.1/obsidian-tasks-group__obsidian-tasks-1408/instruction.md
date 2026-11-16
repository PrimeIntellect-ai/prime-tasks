Multiple 'sort by tag' lines ignore all but last one
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

With the following instructions:

````text
```tasks
sort by tag 2
sort by tag 1
sort by description
```
````

I expect that the results will show:

- all tasks sorted by tag 2, initially
- any tags that have the same tag 2 value will then be sorted by tag 1
- and then any tags that have the same tag 2 and tag 1 will be sorted by description



### Current behaviour

With the above query, the tasks are actually sorted like this:

- all tasks sorted by tag 1, initially
- and then any tags that have the same tag 1 are sorted by description

In other words, tag 2 is ignored in the sort, even though it is supposed to be the highest priority.



### Steps to reproduce

1. Create these tasks

```text
- [ ] random 2 #a #a
- [ ] random 9 #a #b
- [ ] random 4 #a #c

- [ ] random 7 #b #a
- [ ] random 1 #b #b
- [ ] random 5 #b #c

- [ ] random 3 #c #a
- [ ] random 8 #c #b
- [ ] random 6 #c #c
```

2. Create this tasks block:

````text
```tasks
path includes [whatever the file name or path is of the file containing the test tasks]
sort by tag 2
sort by tag 1
sort by description

hide edit button
hide backlink

```
````

Actual output: Tags are sorted by tag 1 and then description

```markdown
- [ ] random 2 #a #a
- [ ] random 4 #a #c
- [ ] random 9 #a #b
- [ ] random 1 #b #b
- [ ] random 5 #b #c
- [ ] random 7 #b #a
- [ ] random 3 #c #a
- [ ] random 6 #c #c
- [ ] random 8 #c #b
9 tasks
```

Expected output: Tasks are sorted by tag 2 and then tag 1.


```markdown
- [ ] random 2 #a #a
- [ ] random 7 #b #a
- [ ] random 3 #c #a
- [ ] random 9 #a #b
- [ ] random 1 #b #b
- [ ] random 8 #c #b
- [ ] random 4 #a #c
- [ ] random 5 #b #c
- [ ] random 6 #c #c
9 tasks
```


### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [ ] Linux
- [X] macOS
- [ ] Windows

### Obsidian Version

1.1.6

### Tasks Plugin Version

1.19.0

### Checks

- [ ] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

[HIDDEN]
