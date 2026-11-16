zeroUnit erroneously report zeros in color functions
In `2.0-rc` `zeroUnit` will report this:
```css
color: rgb(0, 0, 0);
```

I've been thinking and I don't think we can just exclude certain functions since there are a lot of them in Less, Math and Color for example (full reference: http://lesscss.org/functions/).

I suggest we just ignore all function calls in `zeroUnit`.
