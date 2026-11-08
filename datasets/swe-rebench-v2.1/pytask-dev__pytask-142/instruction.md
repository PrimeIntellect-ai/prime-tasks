ENH: Do not display skipped tasks with default verbosity.
### Issue

When tasks are selected with expressions, the skipped tasks are still displayed in the live table and pollute the terminal.

### Suggestion

- Do not display tasks which are skipped, persisted, etc. when verbosity is set to 1
- Display those tasks when verbosity is set to 2.
