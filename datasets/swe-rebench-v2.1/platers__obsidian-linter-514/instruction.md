Bug: Incorrect addition of H1 when the note only contains front-matter
## Describe the Bug

I had a note that only consisted of YAML front-matter. I activated the linter option "Inserts the file name as an H1 if no H1 exists.". When you lint the file, the heading gets added after the closing `---` of the front-matter and a blank line gets inserted after the opening `---`.

## How to Reproduce

Steps to reproduce the behavior:

1. Create a new note with an arbitrary title.
2. Add a frontmatter block to it.
3. Make sure there is no new-line at the end of the file.
4. Go to the linter options and activate "Inserts the file name as an H1 if no H1 exists." in the heading options.
5. Lint the note.

Example to reproduce issue with

Say we have a note with title `Test note` which has the following contents:

``` markdown
---
hello: test
---
```

Note: there is no ending new-line after the closing `---`.

After a lint, the note gets converted to:

```markdown
---

hello: test
---# Test note
```

## Expected Behavior

The note gets properly linted, and the title of the note gets added below the YAML front-matter.

``` markdown
---
hello: test
---

# Test note
```

## Screenshots

<img width="711" alt="Screenshot 2022-11-25 at 14 50 59" src="https://user-images.githubusercontent.com/22298999/203989698-c9d406ea-14a4-49d0-b6c3-30668af4f9ff.png">
<img width="711" alt="Screenshot 2022-11-25 at 14 51 12" src="https://user-images.githubusercontent.com/22298999/203989704-fa875236-d52a-4ed0-aae7-84cbed5afa19.png">

## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

I'm happy to work on a fix if you give me pointers on where to look at. Awesome job, btw ❤️
