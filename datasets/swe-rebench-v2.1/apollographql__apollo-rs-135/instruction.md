Could not parse type ListItem
I'm trying to parse this: ~~`query($foo:[Int]){}`~~ `query($foo:[Int]){x}` but I'm getting these errors:

```
ERROR@11:12 "expected a Type" [,
ERROR@11:12 "expected a Variable Definition" [
ERROR@11:12 "expected R_PAREN, got [" [
```

[edit: the example query was wrong because there was no selection. I added a selection. The error did not change.]
