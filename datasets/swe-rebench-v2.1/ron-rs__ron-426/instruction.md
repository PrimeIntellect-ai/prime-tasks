Pretty Print Multiline String
Is it possible to add a config to `PrettyConfig` to allow `to_string_pretty` to print mulitline string as it is? For example, print
```
"a
b
c"
```
instead of `"a\nb\nc"`?

### Additional contract requirements

The default pretty-printing configuration continues to escape string line breaks. The public builder `PrettyConfig::escape_strings(false)` opts out of this behavior: pretty-printed multiline strings contain literal line breaks, and parsing the output recovers the original string.
