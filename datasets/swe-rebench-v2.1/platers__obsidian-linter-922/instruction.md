Bug: header refactor alsto Capilizer words inside double (`)(`)
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

Linter/Capitalize Headings style code inside `$= dataview etc` or `class: ` so it make the code break.

## How to Reproduce
1. turn on `Hedings should be formatted with capitalization`
2. make it `ALL CAPS`
3. create a note with the next header
4.

```markdown
## `= durationformat(date(this.day) - date(2023-10-06),"dd")` th days passed since the Black Shabbat
```
5. apply linter
6. you will see

``` markdown
## `= DURATIONFORMAT(DATE(THIS.DAY) - DATE(2023-10-06),"DD")` TH DAYS PASSED SINCE THE BLACK SHABBAT
```

## Expected Behavior

``` markdown
## `= durationformat(date(this.day) - date(2023-10-06),"dd")` TH DAYS PASSED SINCe THE BLACK SHABBAT
```

## Screenshots

If applicable, add screenshots to help explain your problem.

## Device

- [x] Desktop
- [ ] Mobile

### Additional contract requirements

- With the ALL CAPS style selected, preserve inline code exactly as written and convert all heading text outside inline code to ALL CAPS. In the expected example, “SINCe” should therefore be “SINCE.”
