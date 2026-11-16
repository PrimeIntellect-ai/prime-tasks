[BUG] Rule crash while typing in-editor due to `class` shorthand not containing a value.
**Describe the bug**
A `class` or `className` shorthand prop crashes 7 different rules in the project, causing an error to pop up in-editor:
```
ESLint: Cannot read properties of null (reading 'type') Occurred while linting
```

**To Reproduce**
Steps to reproduce the behavior:
1. Enable the `enforces-shorthand` rule.
2. Type: `<div class></div>`.

**Expected behavior**
No error

**Environment (please complete the following information):**
 - OS: macOS
 - Softwares + version used:
     -  VSCode 1.70.2
     -  npm 8.5.5, node v16.14.2

**Additional context**
Easily reproducible with tests, PR incoming
