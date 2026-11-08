isPostalCode: Iran (IR) RegExp is too permissive, matches invalid postal codes
The current regexp is too permissive, so it will match strings that should not be valid postal codes by themselves
[HIDDEN]

`\b(?!(\d)\1{3})[13-9]{4}[1346-9][013-9]{5}\b`

This results in the following strings being passed as valid postalcodes:
* test123 4351666456 test456
* this should not be 5614736867 a valid post code


PR with a fix is coming in a few moments

### Additional contract requirements

- Iranian postal-code validation must require the postal code to match the entire input; surrounding text must not make an otherwise invalid value valid.
