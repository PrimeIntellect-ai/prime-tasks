'sort by path' handles mixed case differently to 'sort by description'
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

I would expect all sorting of text fields to give consistent order when comparing upper and lower case strings.
Either Capitals first or Lower case first.



### Current behaviour

The current behaviour is that they differ, as these two tests show:

```ts
    it('sort by description', () => {
        // Arrange
        const sorter = new DescriptionField().createNormalSorter();

        // Assert
        // ~~case-sensitive - capitals come last~~
        // ~~TODO WHY? In description searches, capitals appear to come first.~~
        // UPDATE: Description sorting ignored case - I didn't have enough tests to realise that.
        expectTaskComparesAfter(sorter, with_description('AAA'), with_description('aaa'));
    });
```

```ts
    it('sort by path', () => {
        // Arrange
        const sorter = new PathField().createNormalSorter();

        // Assert
        // case-sensitive - capitals come first
        expectTaskComparesBefore(sorter, with_path('c/D.md'), with_path('c/d.md'));
    });
```

### Steps to reproduce

See the tests above.

I can't demo this on a Mac as mine has the default behaviour of filenames not being case-sensitive, so I can't make two files in the same path, differing only by case.



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

The issue is the different implementations of sorting for those two fields:

https://github.com/obsidian-tasks-group/obsidian-tasks/blob/b20a44c863a93135ca32b80f4b7d522490b59ab5/src/Query/Filter/DescriptionField.ts#L44-L50

https://github.com/obsidian-tasks-group/obsidian-tasks/blob/b20a44c863a93135ca32b80f4b7d522490b59ab5/src/Query/Filter/PathField.ts#L29-L39

In newer code, I've added this as the default sorting implementation for text fields:

https://github.com/obsidian-tasks-group/obsidian-tasks/blob/b20a44c863a93135ca32b80f4b7d522490b59ab5/src/Query/Filter/TextField.ts#L94-L105

I do think that wherever possible, the sorting of string fields should use locale-aware searches.

So the trivial fix for this is:

1. [HIDDEN]
2. Update the `PathField` test that shows the opposite sorted order to what is expected
3. Remove the comment in `DescriptionField.test.ts` that remarks on the difference in behaviour.

See also the following - further examples of the value of using more sophisticating sorting code, rather than rolling our own:

- https://github.com/obsidian-tasks-group/obsidian-tasks/issues/1429
- https://github.com/obsidian-tasks-group/obsidian-tasks/issues/1430

### Additional contract requirements

- Path and description sorting must use a consistent ordering for mixed-case text, so uppercase and lowercase variants are not ordered differently between these fields.
