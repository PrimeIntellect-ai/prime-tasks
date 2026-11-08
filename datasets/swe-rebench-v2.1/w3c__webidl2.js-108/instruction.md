Comment order parsing bug
Give the following input (top level):

```
/* first */
// second
```

The parser is returning:
```
// second
/* first */
```

As json:

```JS
[
  {
    "type": "line-comment",
    "value": " second"
  },
  {
    "type": "multiline-comment",
    "value": " first "
  },
  {
    "type": "ws",
    "value": "\n"
  }
]```
