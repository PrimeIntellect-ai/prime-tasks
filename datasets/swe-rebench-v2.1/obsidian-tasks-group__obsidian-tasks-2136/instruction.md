Work out how to prevent `path regex matches /a/b/c/d/` from confusingly only searching `path regex matches /a/`.
From code review in https://github.com/obsidian-tasks-group/obsidian-tasks/pull/1015

> Open an Issue against this?
>
> Fixable with another regex. 😉😂🤣🤪

_Originally posted by @elight in https://github.com/obsidian-tasks-group/obsidian-tasks/pull/1015#discussion_r945393546_

### Expected Behavior

```text
path regex matches /a/b/c/d/
```

Should give an error message, something along the lines of:

> An unescaped delimiter must be escaped; in most languages with a backslash (\)

So that the user can work out that the correct search is:

```text
path regex matches /\a/b\/c\/d/
```

### Current behaviour

The search proceeds, doing this search, and potentially matching many unwanted hits:

```text
path regex matches /a/
```

### Steps to reproduce

Construct a search similar to the above, and run in Tasks 1.12.0, when it is relased.

Or open the file `Regular Expression Searches.md` in the Tasks-Demo vault, and read the section 'Extra slashes truncate the query'

Or run this test, and remove all the `failing` text:

https://github.com/obsidian-tasks-group/obsidian-tasks/blob/60c5cd45d6d236f3fe8b4b1628b03953a4c19867/tests/Query/Filter/PathField.test.ts#L158-L187

### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [ ] Linux
- [x] macOS
- [ ] Windows

### Obsidian Version

0.15.9

### Tasks Plugin Version

1.12.0 (pre-release)

### Checks

- [ ] I have tried it with all other plugins disabled and the error still occurs

### Suggested fix


#### Current behaviour

I believe that the problem is that the regular expression is the problem:

https://github.com/obsidian-tasks-group/obsidian-tasks/blob/114c8cd7614bbcba1f746b742658c9bcf99fd5bf/src/Query/Filter/TextField.ts#L32-L33

It gets as much of the regex as is valid, and ignores any later text.

This hides any errors from the user.

#### Requested behaviour

- [HIDDEN]
- and then for Tasks to check if there were any error messages detected
- and if there was an error, report it the the user and then refuse to search.

In other words, I don't feel that it is Tasks' job to validate the regex supplied to the user.

I feel that the regex library should do this, as it is bound to do a better and more informative job than we can possibly do.

### Additional contract requirements

Regex filters must evaluate the complete user-supplied expression rather than
truncating it at an embedded slash. This applies to every field that supports regex
searches, not only paths. The query

```text
path regex matches /a/b/c/d/
```

is valid and searches using the whole path `/a/b/c/d/`; it must not be silently
truncated to `path regex matches /a/`. This supersedes the earlier suggested
error outcome for that same example.

If the supplied expression is invalid, Tasks must report the error to the user and
refuse to search.
