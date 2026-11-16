Day 7
Good morning! Here's your coding interview problem for today.

This problem was asked by Facebook.

Given the mapping a = 1, b = 2, ... z = 26, and an encoded message, count the number of ways it can be decoded.

For example, the message '111' would give 3, since it could be decoded as 'aaa', 'ka', and 'ak'.

You can assume that the messages are decodable. For example, '001' is not allowed.

### Additional contract requirements

- Expose the decoding operation as `NumberOfDecodings(str string) int`.
- A `0` digit never decodes to a letter on its own; it is only valid as the second digit of the two-digit mappings `10` and `20`. For example, `"10"` has exactly one decoding (`j`), `"20"` has exactly one decoding (`t`), and `"101"` has exactly one decoding (`ja`).
