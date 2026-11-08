Boolean conditions: strange logging
Diktat version:     implementation("org.cqfn.diktat:diktat-gradle-plugin:1.0.0-rc.1")
Running via gradle script.

```
 if (doubleQuoteIsClosed && singleQuoteIsClosed) {
                // FixMe: isLetterOrDigit is not supported in Kotlin 1.4, but 1.5 is not compiling right now
                if (!setOf('_', '-', '.', '"', '\'').contains(ch) && !ch.isLetterOrDigit())
                    throw TomlParsingException(
                        "Not able to parse the key: [$rawContent] as it contains invalid symbols." +
                                " In case you would like to use special symbols - use quotes.",
                        lineNo
                    )
            }
```
```
line 2:0 no viable alternative at character '/'
line 2:1 no viable alternative at character '/'
line 2:8 no viable alternative at character ':'
line 2:10 mismatched input 'isLetterOrDigit' expecting RPAREN
line 2:54 no viable alternative at character '.'
line 2:56 no viable alternative at character ','
line 2:63 no viable alternative at character '.'
```

### Additional contract requirements

- When formatting `foo && bar &&` followed by the comment `// FixMe: isLetterOrDigit is not supported in Kotlin 1.4, but 1.5 is not compiling right now` and then `setOf('_', '-', '.', '"', '\'').baz() && ch.isLetterOrDigit()`, return exactly `(C & D &  B & A)`.
- Processing a Boolean condition that contains a comment must not emit spurious parser diagnostics.
