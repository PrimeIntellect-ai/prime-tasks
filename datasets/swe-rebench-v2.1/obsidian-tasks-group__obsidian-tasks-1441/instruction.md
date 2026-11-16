Sorting by text fields should do proper natural sorting
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

Given these tasks:

```
- [ ] 8 Eight
- [ ] 9 Nine
- [ ] 10 Ten
- [ ] 11 Eleven
```

And this tasks block:

````
```tasks
sort by description
```
````

The result should be tasks displayed in this order:

```
- [ ] 8 Eight
- [ ] 9 Nine
- [ ] 10 Ten
- [ ] 11 Eleven
```



### Current behaviour

The actual results are shown in this order:

```
- [ ] 10 Ten
- [ ] 11 Eleven
- [ ] 8 Eight
- [ ] 9 Nine
```

Because `1` sorts before `8` - and the digits are not interpreted as numbers.

### Steps to reproduce

See the tasks and query block in 'Expected Behavior' above.

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

The [Stack Overflow answer](https://stackoverflow.com/a/38641281/104370) shows a solution:

```ts
myArrayObjects = myArrayObjects.sort(function(a, b) {
  [HIDDEN]
});
```

See the answer for more details.

### Additional contract requirements

- When sorting by text fields, digit sequences within the text must be ordered by numeric value rather than lexicographically. For example, `9` sorts before `11`, including when the digits appear after other text.
