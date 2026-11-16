Generated Python code doesn't cope with multi-line regexs
Consider:

```
myrule = /(?x)
   foo
   bar
/ $ ;
```
This generates:

```
self._pattern(r'(?x) \n   foo\n   bar\n')
```
Which will look for literal newlines in the string, rather than being ignored.

### Additional contract requirements

Generated parser code must preserve physical line breaks in a verbose-mode regular expression as ignorable whitespace. Explicitly escaped newline sequences in the same expression must retain their regex meaning.
