Panic when parsing invalid comments `<!-->`
On the following input quick XML 0.28-2 panics with ` 'slice index starts at 3 but ends at 1', quick-xml-0.28.2/src/reader/parser.rs:104:22`

```xml
<?xml version="1.0" encoding="utf-8"?>
<sparql xmlns="http://www.w3.org/2005/sparql-resu:lts#">
<head>
        <variable name="str"/>
</head>
<results>
        <result></result> <!-->
        <result></resulhtmlns>=
```

I believe this error is caused by [HIDDEN].

### Additional contract requirements

- Parsing a malformed, unterminated comment such as `<!-->` must return a parsing error rather than panic.
