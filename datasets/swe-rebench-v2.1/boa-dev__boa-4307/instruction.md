Boa can't parse a class with a keyword as name
<!--
Thank you for reporting a bug in Boa! This will make us improve the engine. But first, fill the following template so that we better understand what's happening. Feel free to add or remove sections as you feel appropriate.
-->

**Describe the bug**
Boa can't parse a file containing `class of {}`. I found such a javascript file in some minified JS code.

<!-- E.g.:
The variable statement is not working as expected, it always adds 10 when assigning a number to a variable"
-->

**To Reproduce**
Steps to reproduce the issue, or JavaScript code that causes this failure.

This JavaScript code reproduces the issue:
```javascript
class of {}
```

**Expected behavior**
A class with name `of` should be created, like in browsers and node.

**Build environment (please complete the following information):**

- OS: Arch Linux
- Version: 0.20.0
- Target triple: `x86-unknown-linux-gnu`
- Rustc version: rustc 1.87.0 (17067e9ac 2025-05-09)

**Additional context**
N/a

<!-- E.g.:
You can find more information in [MDN](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/var).
-->
