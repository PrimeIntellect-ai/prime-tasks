The 'sort by description' order is incorrect after stripping formatting
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

Given these tasks - in a file called `description sorting`:

```
- [ ] *un-format* me 4
- [ ] **un-format** me 1
- [ ] _un-format_ me 5
- [ ] [[un-format]] me 7
- [ ] [[un-format|un-format]] me 6
- [ ] [un-format] me 8
- [ ] =un-format= me 3
- [ ] ==un-format== me 2
```

And this tasks block:


```tasks
filename includes description sorting
sort by description
```

The documentation says that:

> Sorting by description should take into account [[Links]] and [Links with an|Alias] (note pipe). It should also take into account *italics* and ==highlights==. It sorts by the text that’s visible in preview mode.

And so I would expect the sorting to successfully strip out all formatting characters - so that the 'un-format' strings are all identical during sorting, and the tasks **should be displayed in the order of the digit at the end of their line.**

So the results should be in this order:

![image](https://user-images.githubusercontent.com/4840096/209588222-385736e5-c514-4544-a978-91af0f7fa22e.png)


#### Edit 2022-12-27

It turns out that `=un-format= me 3` was not valid formatting, so should not have been stripped.

However, `__bold__` should have been recognised.

### Current behaviour

The actual result is this:

![image](https://user-images.githubusercontent.com/4840096/209564985-eb864814-84c1-4f72-aa17-baa05ec2ebad.png)

The fact that the tasks are not sorted purely in the order their trailing digit shows that not all the the formatting characters have been removed.

### Steps to reproduce

See the tasks and query block in 'Expected behavior' above.

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

### Tests that reveal what's going on

I discovered this when writing tests of the current behaviour of sorting tasks by description.

These tests capture the current behaviour:

https://github.com/obsidian-tasks-group/obsidian-tasks/blob/b20a44c863a93135ca32b80f4b7d522490b59ab5/tests/Query/Filter/DescriptionField.test.ts#L299-L343

There are obvious errors here like `**bold**` being converted to `bold**bold**` instead of to `bond`.

And stray `]` being left.

### Location of the issue

https://github.com/obsidian-tasks-group/obsidian-tasks/blob/b20a44c863a93135ca32b80f4b7d522490b59ab5/src/Query/Filter/DescriptionField.ts#L58-L87

Putting `{}` around the 3 blocks shows the error on the new line 79 - where the middle block has a remnant of the first block - see `startsWithLinkRegex` shown in red in this image:

![image](https://user-images.githubusercontent.com/4840096/209565461-8a6ade7a-8e81-424b-b153-4be69cac537a.png)
