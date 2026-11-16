Tasks does not recognise dates 2 or more spaces after the emoji
## Expected Behavior

That all three of these tasks should be treated as having a date:

```markdown
- [ ] 0 space(s) between emoji and date 📅2022-07-17
- [ ] 1 space(s) between emoji and date 📅 2022-07-17
- [ ] 2 space(s) between emoji and date 📅  2022-07-17
```

And so this should match all three task lines:

````text
```tasks
has due date
```
````

<!--- Tell us what should happen -->

## Current Behavior

The above filter only matches the first two tasks:

![image](https://user-images.githubusercontent.com/4840096/179395515-93bfbcc2-ce61-4e4f-a859-ecf82ce74c2c.png)


Whilst writing the docs for the new auto-suggest feature, I have had to write:

> - Tasks currently **ignores date and recurrence emojis with 2 or more spaces after the emoji** and before its value.
>   - Because the spaces between the emojis and the following text are invisible in most views, this is a serious limitation.
>   - Please be careful to ensure you have only a single space in these locations.

I believe this silent failure to recognise emoji'a values if the emoji is followed by more than 1 space is a blocker for releasing the auto-suggest feature.

<!--- Tell us what happens instead of the expected behavior -->

## Steps to Reproduce
<!-- Which exact steps can I take to reproduce the issue? -->

Create these tasks:

```markdown
- [ ] 0 space(s) between emoji and date 📅2022-07-17
- [ ] 1 space(s) between emoji and date 📅 2022-07-17
- [ ] 2 space(s) between emoji and date 📅  2022-07-17
```

And prevue the results with this block:

````text
```tasks
has due date
```
````

## Context (Environment)
* Obsidian version: 0.15.6
* Tasks version: A pre-release build of 1.9.0
* [ ] I have tried it with all other plugins disabled and the error still occurs

## Possible Solution
<!--- Not obligatory, but suggest a fix/reason for the bug, if you have an idea -->

[HIDDEN]

## Extra info - recurring tasks works

I was expecting that the same problem would occur with recurrence, because the regex also has ` ?`

```typescript
    public static readonly recurrenceRegex = /🔁 ?([a-zA-Z0-9, !]+)$/iu;
```

But these:

```markdown
- [ ] 0 space(s) between emoji and 🔁every day
- [ ] 1 space(s) between emoji and 🔁 every day
- [ ] 2 space(s) between emoji and 🔁  every day
```

With this:

````text
```tasks
is recurring
```
````

Gives this:

![image](https://user-images.githubusercontent.com/4840096/179395863-bc6eaf51-7502-433d-9c7c-49b01a507533.png)

So some later code is likely stripping the extra space character from the start of the recurrence text.

### Additional contract requirements

When reading task lines, recognize a valid date after the due-date, done-date, scheduled-date, or start-date emoji when it is followed by zero, one, or multiple spaces. The `has due date` query must match the three demonstrated tasks. Recurrence rules following 🔁 must continue to be recognized with zero, one, or two spaces before the rule.
