not to match diff: Highlight special chars and newlines in the matched part
``` js
var text = "foobar\n";
expect(text, 'not to match', /\s+/);
```

When the above assertion fails it would be nice to mark up the special characters in the part of the diff that highlights the match that shouldn't have been there. Right now just looks like:

```
expected 'foobar\n' not to match /\s+$/

foobar

```

... which isn't that easy to decipher.
