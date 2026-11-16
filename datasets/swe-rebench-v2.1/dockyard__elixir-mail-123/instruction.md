Recipient value parsing doesn't parse names where content of name is an email address
<!-- BUG TEMPLATE -->
## Version
v0.2.1

## Test Case

```elixir
Mail.Parsers.RFC2822.parse_recipient_value("\"an@email.com\" <an@email.com>")
```

The return value is `["an@email.com\"", "an@email.com"]`
While it should have been `[{"an@email.com", "an@email.com"}]` since, yes this is terrible, the "name" for that person is the email address.
This is from a real email (I did alter the address) so it's a real issue.

## Steps to reproduce

Invoke
```elixir
Mail.Parsers.RFC2822.parse_recipient_value("\"an@email.com\" <an@email.com>")
```
Inside an `IEx` session

## Expected Behavior
I'd expect `"\"an@email.com\" <an@email.com>"` to be parsed as a name + email address, not as 2 email addresses.
A list of two elements (two strings) was returned, while the expected behavior is that a list of one element (a tuple of name+email address) is returned

## Actual Behavior

Two emails were found (a list of two elements is returned) `["an@email.com\"", "an@email.com"]`
