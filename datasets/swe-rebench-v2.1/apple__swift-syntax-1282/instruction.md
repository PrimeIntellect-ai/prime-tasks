If an attribute is put on a statement, the entire statement is classified as unexpected
### Issue Kind

Bad Diagnostic Produced

### Source Code

```swift
func test1() {
  #^TEST_1^#@s return
}
```
(from `testAttributesOnStatements`)

### Description

This should eat `@s` as unexpected tokens and parse `return` as a statement instead of complaining
```
Unexpected text '@s return' found in function
```

### Additional contract requirements

The recovery for misplaced attributes is observable through the parser's
diagnostics, which must use the following exact messages.

- When an attribute is placed before a statement, the attribute is consumed as
  unexpected tokens and the statement that follows is still parsed. The
  unexpected attribute is reported with the message
  `unexpected code '<attribute>' before '<keyword>' statement`, where
  `<attribute>` is the attribute text (for example `@s` or `@unknown`) and
  `<keyword>` is the keyword of the statement that follows (for example
  `return`). For instance, `@s return` produces
  `unexpected code '@s' before 'return' statement` and `@unknown return`
  produces `unexpected code '@unknown' before 'return' statement`.

- When unexpected tokens (including attributes) appear before a switch case
  label, they are consumed as unexpected tokens and reported with the message
  `unexpected code '<tokens>' in switch case`, where `<tokens>` is the text of
  the unexpected tokens. For instance, `@garbage @moreGarbage default:`
  produces `unexpected code '@moreGarbage' in switch case`,
  `@unknown(garbage) case _:` produces `unexpected code '(garbage)' in switch case`,
  a second `@unknown` before a `case` label produces
  `unexpected code '@unknown' in switch case`, and `@unknown @garbage(foobar)`
  before a `case` label produces `unexpected code '@garbage(foobar)' in switch case`.


- For an attribute before a statement, locate the diagnostic at the beginning of the attribute.
