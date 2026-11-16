stripPrefix and stripSuffix
PureScript provides [`stripPrefix`][1] and [`stripSuffix`][2]:

```purescript
stripPrefix :: Pattern -> String -> Maybe String
stripSuffix :: Pattern -> String -> Maybe String
```

I believe Sanctuary should do so too. Today I found myself wanting `stripSuffix` (in Haskell), so I now see the utility. :)


[1]: https://pursuit.purescript.org/packages/purescript-strings/2.1.0/docs/Data.String#v:stripPrefix
[2]: https://pursuit.purescript.org/packages/purescript-strings/2.1.0/docs/Data.String#v:stripSuffix

### Additional contract requirements

`stripPrefix(prefix, s)` and `stripSuffix(suffix, s)` accept two strings. When the first string matches the beginning or end of the second string, respectively, the result is `Just` containing the remainder after removing the match. This includes `Just('')` when a non-empty match consumes the entire input. When the first string does not match, the result is `Nothing`.
