\char renders `\~ as space
This looks similar to #1262, where `\verb` rendered `~` as space.

**Describe the bug:**
KaTeX renders ``\char`\~`` as a space.

**(La)TeX code:**
The code of (La)TeX you tried to render:
```latex
\text{\char`\~}
```

**Expected behavior:**
LaTeX renders the same input as as a (raised) tilde.

**Screenshots:**
QuickLaTeX renders ``!\text{\char`\~}!`` as:
<img width="695" alt="Screenshot" src="https://user-images.githubusercontent.com/18308236/114322180-0da2da00-9b1f-11eb-97db-430ec7f97f89.png">


**Environment (please complete the following information):**
 - KaTeX Version: Online demo at https://katex.org

**Additional context:**
The same happens in math mode. ``\char`\c`` works correctly for all other characters `c` that I've tried.

### Additional contract requirements

- `\char`\~` renders the literal tilde character `~` (U+007E), not a space, in both math and text mode.
- The reported input `\text{\char`\~}` renders the literal tilde character `~`.
