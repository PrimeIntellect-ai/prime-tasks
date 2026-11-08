Real multiple line problem
Hi,
But what about variables containing real newlines?
for example:

```
# .env.example
FOO=baz
MULTILINE_FOO='{
    "first": 1,
    "second": 1
  }'
BAR=baz
```
it is a real work example with `python-dotenv`
and dotenv-linter doesn't work with them:
```
dotenv-linter .env.example
Checking .env.example
.env.example:2 QuoteCharacter: The value has quote characters (', ")
.env.example:3 IncorrectDelimiter: The "first": 1, key has incorrect delimiter
.env.example:3 KeyWithoutValue: The "first": 1, key should be with a value or have an equal sign
.env.example:3 LeadingCharacter: Invalid leading character detected
.env.example:3 LowercaseKey: The "first": 1, key should be in uppercase
.env.example:3 UnorderedKey: The "first": 1, key should go before the FOO key
.env.example:4 IncorrectDelimiter: The "second": 1 key has incorrect delimiter
.env.example:4 KeyWithoutValue: The "second": 1 key should be with a value or have an equal sign
.env.example:4 LeadingCharacter: Invalid leading character detected
.env.example:4 LowercaseKey: The "second": 1 key should be in uppercase
.env.example:4 UnorderedKey: The "second": 1 key should go before the FOO key
.env.example:5 KeyWithoutValue: The }' key should be with a value or have an equal sign
.env.example:5 LeadingCharacter: Invalid leading character detected
.env.example:6 UnorderedKey: The BAR key should go before the FOO key

Found 14 problems
```

### Additional contract requirements

A quoted environment-variable value may span multiple physical lines. Treat the complete quoted value as one entry; do not lint its continuation lines as independent entries.
