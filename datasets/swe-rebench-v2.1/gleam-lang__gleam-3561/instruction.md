Improve suggestions for inexhaustive case expression error
<!--
Gleam is post-v1, so breaking changes are not possible.

Any new addition to the language itself needs to enable something that is not possible in Gleam today, and solve existing pain-points.

For anything other than trivial and uncontroversial additions please make a GitHub discussion before making an issue. https://github.com/gleam-lang/gleam/discussions/categories/ideas-suggestions
-->

Currently, for this code:
```gleam
case True {}
```

The compiler produces this error:

```
error: Inexhaustive patterns
  ┌─ FILE
  │
5 │ ╭   case True {
6 │ │
7 │ │   }
  │ ╰───^

This case expression does not have a pattern for all possible values. If it
is run on one of the values without a pattern then it will crash.

The missing patterns are:

    _
```

This is not super helpful; it would be much better to suggest `True` and `False` as missing patterns instead. Also, #2957 cannot be implemented in a particularly useful manner until this is improved. (See [here](https://github.com/gleam-lang/gleam/pull/3537#discussion_r1723230130))

Edit: There was some confusion about the above code. The matching on the literal value `True`, has nothing to do with this. It's merely to demonstrate this error.

### Additional contract requirements

- For an empty case expression over a Boolean, list the missing patterns in this order: `False`, then `True`.
- For an empty case expression over a list, list the missing patterns in this order: `[]`, then `[_, ..]`.
