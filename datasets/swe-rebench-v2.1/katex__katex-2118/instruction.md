\@ifnextchar should consume spaces
**Describe the bug:**
As [reported](https://github.com/KaTeX/KaTeX/issues/2114#issuecomment-540431307) by @JohnTasto, `\@ifnextchar` should ignore spaces that follow it, but our implementation doesn't.  [HIDDEN]

**To Reproduce:**
```latex
\def\x#1{\@ifnextchar x{yes}{no}}
\x{}x \\
\x{} x
```
![image](https://user-images.githubusercontent.com/2218736/66590245-52cb0200-eb5e-11e9-8d17-311a1e940292.png)

**Expected behavior:**
LaTeX produces:
![image](https://user-images.githubusercontent.com/2218736/66590309-7beb9280-eb5e-11e9-96fa-5b313a6bb007.png)

**Additional context:**
Here's the relevant LaTeX implementation of `\@ifnextchar`:

```latex
\long\def\@ifnextchar#1#2#3{%
  \let\reserved@d=#1%
  \def\reserved@a{#2}%
  \def\reserved@b{#3}%
  \futurelet\@let@token\@ifnch}
\let\kernel@ifnextchar\@ifnextchar
[HIDDEN]
\def\:{\let\@sptoken= } \:  % this makes \@sptoken a space token
[HIDDEN]
```

This is difficult code to read (because dealing with spaces in TeX is hard, and `\futurelet` is tricky), but here's a translation:

`\@ifnextchar{CHAR}{THEN}{ELSE}`:
* Stores its arguments
* Get next character
* Call `\@ifnch`

`\@ifnch`:
[HIDDEN]
* Otherwise, check the character against CHAR and expand to THEN or ELSE accordingly.

In other words, **consume** spaces and check the next character without consuming it.  Our current implementation does the latter but not the former.

### Additional contract requirements

- Before checking the next character, `\@ifnextchar` consumes all consecutive spaces following its arguments. The next non-space character is checked without being consumed.
