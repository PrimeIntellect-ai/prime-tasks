'sort by tag' should do case-insensitive sorting
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

In the Tasks-Demo vault, the following query should show tasks in tag order, regardless of case.
So tags beginning `#context...` should come before `#XX`

````
```tasks
sort by tag
sort by description
tag regex matches /./
```
````

### Current behaviour

This is the results as of Tasks 1.20.0:

![image](https://user-images.githubusercontent.com/4840096/209714652-df766046-050c-4e77-b2ff-27f3a1802c67.png)

Note how `#XX` comes before `#context/...`


### Steps to reproduce

Open the Tasks-Demo vault (see [these notes](https://github.com/obsidian-tasks-group/obsidian-tasks/blob/main/CONTRIBUTING.md#how-do-i-test-a-github-build-of-the-tasks-plugin) if you don't know how)
Then view in Reading or Live Preview modes.

### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [ ] Linux
- [X] macOS
- [ ] Windows

### Obsidian Version

1.1.9

### Tasks Plugin Version

1.20.0

### Checks

- [ ] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

[HIDDEN]

### Additional contract requirements

- When two tags differ only by case, sort the lowercase spelling before the uppercase spelling; in particular, `aaaa` must sort before `AAAA`.
