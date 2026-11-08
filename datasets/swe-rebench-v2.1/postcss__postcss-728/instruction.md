CSS syntax error reporting wrong line/column position
@Arcanemagnus originally filed this as an issue with stylelint (https://github.com/stylelint/stylelint/issues/718):

With this CSS file:

```css
.s["] {
}
/* "" */
```

There is a CSS syntax error that reports the column of the unclosed quote on line 1 as being 18, which is far past the end of the line. It seems like it is counting all characters between the first quote and the next one as part of the line? When the comment with the `"` is removed the proper value is returned. If that comment is brought to the same line as the initial `"` the issue disappears as well.

Based on a report initially filed here: https://github.com/AtomLinter/linter-stylelint/issues/79.
![image](https://cloud.githubusercontent.com/assets/427137/12932639/88718672-cf38-11e5-87c8-94a7376ada7c.png)




This is different from #725 because the error is thrown during the tokenize step (so it's not using `node.positionBy()`).

I think that the syntax error is causing weird problems with text editor plugins, because it claims that things are happening in positions that do not exist.

Do you think there's a way to make these positions more accurate? If not, maybe text editor plugins just need to do something different when receiving CSS syntax errors from PostCSS?
