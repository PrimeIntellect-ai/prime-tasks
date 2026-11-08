Fix Unicode and Hex Escape Parsing in String/Symbol/CLOB
As per #17, there appears to be an issue around escape processing for Unicode escapes (i.e. `\uHHHH`, `\UHHHHHHHH`, and `\xHH`), we should make sure this is working correctly in parser, because for at least CLOBs, `\xHH` does not appear to process correctly when parsing `clobNewlines.ion` in the test vectors.

### Additional contract requirements

- When parsing string and quoted-symbol values, decode `\xHH`, `\uHHHH`, and `\UHHHHHHHH` escapes into the corresponding character values. The resulting string or symbol value must expose those decoded characters.
- When parsing CLOB values, decode `\xHH` escapes into the corresponding bytes of the CLOB value.
