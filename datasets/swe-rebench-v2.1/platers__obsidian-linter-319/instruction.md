Bug: Line breaks removed between formatted text which is not a list
## Describe the Bug

Line breaks between lines of formatted text are removed. It appears that the linter thinks these lines are part of a list due to the character that the line begins with.


## How to Reproduce

I think it relates to this rule: https://github.com/platers/obsidian-linter/blob/master/docs/rules.md#remove-empty-lines-between-list-markers-and-checklists

Given markdown like this:

```markdown
*Some italicised item:* some detail

**Some bold item:** some other detail
```

The linter removes the break and does this:

```markdown
*Some italicised item:* some detail
**Some bold item:** some other detail
```

## Expected Behavior

I would expect the line break not to be removed.

## Screenshots

N/A

## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

N/A
