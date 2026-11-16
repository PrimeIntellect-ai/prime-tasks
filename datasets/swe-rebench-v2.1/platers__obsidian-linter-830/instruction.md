FR: Exclude quote rules from inline code (single backticks)
## Is Your Feature Request Related to a Problem? Please Describe.

I ran the linter across my vault and notices that it changes something like `` `'Test'` `` to `` `‘Test’` `` when smart quotes are enabled, but in this case it was referring to a string in code.

## Describe the Solution You'd Like

It would be great if there was an option to disable the option for inline code. There are a few other rules which also seem to be deactivated in code blocks but not in inline code (like removing spaces after punctuation) so it could make sense to make an option that is broader and affects more than one rule.

**Please include an example where applicable:**

```markdown
- `'string'`
```

```markdown
- `'string'`
```

## Describe Alternatives You've Considered

You could use a code block but for small snippets especially in the middle of a sentence inline code makes more sense so I ended up disabling the rules that negatively affected my inline code snippets.
