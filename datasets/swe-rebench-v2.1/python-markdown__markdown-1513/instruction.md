Abbreviation extension should not inject markup in mathjax contexts
Assume we have defined an abbreviation

```
*[YAFR]: Yet Another Feature Request
```

Then the following markdown

```markdown
Our function $f_\text{YAFR}$ does some things
```

will be expanded to (something like):

```
Our function $f_\text{<abbr title="Yet Another Feature Request">YAFR</abbr>}$ does some things
```

This will cause a maths renderer like [mathjax](https://www.mathjax.org/) to fail. It is actually rather common to add subindices to notation in maths that refer to abbreviations defined in the text, so I think it would be nice to have the extension not try to expand the text.
