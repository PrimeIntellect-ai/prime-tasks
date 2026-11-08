\providecommand overwrites the existing macro
> Before reporting a bug
- [x] Check [common issues](https://katex.org/docs/issues.html).
- [x] Check the bug is reproducible in [the demo](https://katex.org). If not, check KaTeX is up-to-date and installed correctly.
- [x] Search for [existing issues](https://github.com/KaTeX/KaTeX/issues).

**Describe the bug:**
`\providecommand` overwrites the existing macro if already defined.

**(La)TeX code:**
```latex
\newcommand{\foo}{a}
\providecommand{\foo}{b}
\foo
```

**Expected behavior:**
`\providecommand` should do nothing if the macro already exists.

QuickLaTeX screenshot:
![ss2](https://github.com/KaTeX/KaTeX/assets/2741668/efbbb2cd-9437-4fdc-a979-18fa5f784b8b)

**Screenshots:**
![ss1](https://github.com/KaTeX/KaTeX/assets/2741668/11b27021-4cab-41ee-85ed-0985ebda5fa9)


**Environment (please complete the following information):**
 - KaTeX Version: 0.16.9
 - Device: Desktop
 - OS: macOS 14.2.1
 - Browser: Firefox
 - Version: 122.0.1
