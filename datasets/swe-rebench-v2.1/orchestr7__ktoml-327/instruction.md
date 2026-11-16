Parse error with multi-line array of arrays with trailing comma
The following results in an exception when parsing. However, `a = [[1], [2], ]` parses just fine.
```toml
a = [
    [1],
    [2],
]
```

```
Exception in thread "main" com.akuleshov7.ktoml.exceptions.ParseException: Line 1: Expected (]) in the end of ARRAY
	at com.akuleshov7.ktoml.parsers.TomlMultilineString.parseMultiline(TomlMultilineString.kt:76)
	at com.akuleshov7.ktoml.parsers.TomlMultilineString.<init>(TomlMultilineString.kt:35)
	at com.akuleshov7.ktoml.parsers.TomlParser.parseStringsToTomlTree-impl(TomlParser.kt:74)
	at com.akuleshov7.ktoml.parsers.TomlParser.parseLines-impl(TomlParser.kt:36)
```

Worth noting that the following parses fine, so the issue seems to only be with multi-line arrays of arrays with a trailing comma from what I can tell.
```toml
a = [
    1,
    2,
]
```
