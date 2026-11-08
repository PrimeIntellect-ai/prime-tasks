isPostalCode: Belarus (BY) RegExp is too permissive, matches invalid postal codes
The current regexp is too permissive, so it will match strings that should not be valid postal codes.
[HIDDEN]

PR with a fix is coming in a few moments

### Additional contract requirements

- Belarus (BY) postal-code validation must accept exactly six digits: the first is `2`, the second is between `1` and `4`, and the remaining four are digits. Validate the entire input, rejecting any extra characters before or after the code.
