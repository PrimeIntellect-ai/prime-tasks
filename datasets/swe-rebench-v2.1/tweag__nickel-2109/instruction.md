`std.string.find` doesn't properly handle optional capture groups
The regex `(a+)(b)?` should match the string "aa", and `std.string.is_match` agrees. But:

```
nickel> std.string.find "(a+)(b)?" "aa"
{ groups = [  ], index = -1, matched = "", }
```

### Additional contract requirements

- For example, `std.string.find "a(b)?" "ac"` must return `{ groups = [""], index = 0, matched = "a" }`, with an empty string occupying the slot for the unmatched optional capture.
