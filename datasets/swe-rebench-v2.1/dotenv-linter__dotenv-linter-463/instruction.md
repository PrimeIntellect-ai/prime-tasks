Doesn't detect multi-line values if they contain a `=` sign
Example:

```env
MULTILINE="{
    'key': 'value='
}"
```

Result:

```
Checking .env
.env:1 QuoteCharacter: The value has quote characters (', ")
.env:2 IncorrectDelimiter: The 'key': 'value key has incorrect delimiter
.env:2 LeadingCharacter: Invalid leading character detected
.env:2 LowercaseKey: The 'key': 'value key should be in uppercase
.env:2 QuoteCharacter: The value has quote characters (', ")
.env:2 UnorderedKey: The 'key': 'value key should go before the MULTILINE key
.env:3 KeyWithoutValue: The }" key should be with a value or have an equal sign
.env:3 LeadingCharacter: Invalid leading character detected

Found 8 problems
```
