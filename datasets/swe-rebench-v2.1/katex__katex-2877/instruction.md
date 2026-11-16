Error with single backslash at end of line
**Describe the bug:**
(Copying from [a fixed pandoc issue](https://github.com/jgm/pandoc/issues/4134):)

> In LaTeX you can use a backslash `\` followed by any whitespace to produce a regular space, as opposed to an inter-sentence space. The whitespace needn't be a space; it could be a line break.

KaTeX treats a single `\` at the end of the line as an error.

**To Reproduce:**
Steps to reproduce the behavior:
1. Go to https://katex.org
2. Type a single `\` followed immediately by a line break.
3. See `KaTeX parse error: Undefined control sequence: \ at position 1: \̲ ̲`.

**Expected behavior:**
It should produce a regular space instead of a parse error.

**Screenshots:**

<img width="791" alt="Screenshot" src="https://user-images.githubusercontent.com/18308236/112727613-90267980-8f23-11eb-83e9-080c8eef33b7.png">

**Environment:**
 - KaTeX Version: 0.13.0

**Additional context:**
MathJax allows a single backslash at the end of the line.
