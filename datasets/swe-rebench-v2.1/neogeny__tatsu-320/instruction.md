Literal ``None`` is interpreted as a string
When using a construct like
```
null = 'null' value:`None` ;
```
`value` takes the string value `"None"` and not `None`.  `` `None` ``is used in the Tatsu's EBNF grammar in a few places and I have the impression that it is meant to be the `None` object no the `"None"` string. I find it mildly confusing that bot `` `"foo"` `` and `` `foo` `` are interpreted as strings, but I don't think that this can be changed, for backward compatibility.

### Additional contract requirements

- Backtick constants that are Python literals must evaluate to their literal values: `42` yields the integer 42, `True` yields the boolean True, and `None` yields None. A non-literal such as `Something` remains the string "Something".
