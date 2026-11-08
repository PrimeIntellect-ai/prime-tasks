Day 381
Good morning! Here's your coding interview problem for today.

This problem was asked by Paypal.

Read this Wikipedia article on [Base64 encoding](https://en.wikipedia.org/wiki/Base64).

Implement a function that converts a hex string to base64.

For example, the string:

`deadbeef`
should produce:
`3q2+7w==`

### Additional contract requirements

Expose the conversion as `Base64Delegate(hexs string) string` so callers can convert valid hexadecimal input.
