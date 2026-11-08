Behavior change in handling `\` at the very end of `tasks` queries [in Live Preview, due to Obsidian unintended change]
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Steps to reproduce

I recently updated Obsidian Tasks after few months of not updating, and lots of my queries have started returning nearly every task in my vault. Queries which had a final `\`, e.g. in the "leaky" query below, would slow down Obsidian significantly and list all tasks in the vault. (The reason I often have trailing `\` in queries is that I tend to mix/match query snippets and keeping the trailing `\` is robust to changes in that query, e.g. moving that "clause" up or down, or elsewhere).

I found that removing the `\` at the very end of the query restored functionality to what I expected from before updating, properly filtering tasks.

I would say tentatively that this apparent "regression" has cropped up in one of the updates in the past ~six months. If there's an easy methodology for me to quickly "bisect" Tasks plugin versions to narrow down the exact release this happened on, or Obsidian Sync logs I'm unaware of, please let me know. My Sync history only shows in the manifest my recent update to 7.10.2, then updating to 7.11.1, so I can't exactly recall which version I updated *from* when this regression crept in.

#### Simple reproduction

1. Create a new vault
2. Enable community plugins and install Tasks
3. Create two files, `one.md` and `two.md` with the following contents
4. **Switch to Live Preview** (_tested in Obsidian 1.7.4 - this line added by @claremacrae_)
5. Note the difference between the "leaky" and "correct" query in `two.md`. The only difference is the trailing slash. The leaky query "incorrectly" sees the task in `one.md`.
- [ ] (Not yet done by myself) To find the version in which the regression appeared, install progressively older versions of the plugin until slash handling in the "leaky" query is handled the same as in the new "correct" query

##### `one.md`

``````Markdown
# One

## Task

- [ ] one

``````

##### `two.md`

``````Markdown
# Two

## Task

- [ ] two

## Leaky query (trailing slash)

```tasks
( path includes {{ query.file.path }} )\
```

## Correct query (no trailing slash)

```tasks
( path includes {{ query.file.path }} )
```

``````

### Expected Behavior

Queries with trailing `\` should still function properly.

### Current behaviour

Queries with trailing `\` fetch everything in the vault instead of filtering as expected.

### Which Operating Systems are you using?

- [X] Android
- [X] iPhone/iPad
- [ ] Linux
- [ ] macOS
- [X] Windows

### Obsidian Version

1.7.4

### Tasks Plugin Version

7.11.1

### Checks

- [x] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

- [ ] Verify reproduction of this behavior
- [ ] Determine whether this is intended behavior. If so, consider communicating it in docs. If not, proceed...
- [ ] Determine the version in which the behavior change was introduced and find the PR that changed it
- [ ] Consider implementing a "fix" for this "regression" if deemed as such
- [ ] Add a test to the test suite that checks the case of "backslash is the final character in the query before closing backticks"
