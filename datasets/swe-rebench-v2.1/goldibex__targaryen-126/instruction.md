Error when using string.length with empty string:  "Invalid < expression: Left and right sides types are differents"
When the rules contain something like:

```js
"bio": {
  ".validate": "newData.isString() && newData.val().length < 100"
}
```

And testing with a write with `"bio": ""`, targaryen throws an error:

```
Error: newData.val().length < 100: Invalid < expression: Left and right sides types are differents.
```

If I test by having a non-empty string for `bio`, it works.
