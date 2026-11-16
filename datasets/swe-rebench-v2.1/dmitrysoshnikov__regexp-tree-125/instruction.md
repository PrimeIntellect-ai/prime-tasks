`/\e/u` should throw
`/\e/u` is an invalid regular expression: https://mathiasbynens.be/notes/es6-unicode-regex#impact-syntax

So instead of parsing, I’d expect this to throw:

```
$ regexp-tree -e '/\e/u'
{
  "type": "RegExp",
  "body": {
    "type": "Char",
    "value": "e",
    "kind": "simple",
    "escaped": true
  },
  "flags": [
    "u"
  ]
}
```
