Proposal: Allow $number() to handle strings with leading '0' characters
Consider the following input:
`{"serialNumber": "ABC-1234"}`
with the following JSONata expression:
`{"isUnderThreshold": (serialNumber ~> $substringAfter('-') ~> $number()) < 5000}`
Naturally the result is
`{"isUnderThreshold": true}`

However, consider the input:
`{"serialNumber": "ABC-0123"}`
 with the same expression.  Intuitively, one would expect that the end result would be the same. However, the end result is the error:
`Unable to cast value to a number: "0123"`
This is because the $number function as designed only handles legal JSON numbers which do not allow leading 0s.

Ideally, it would be nice if this rule was relaxed slightly to allow leading '0' characters.  Otherwise, I would have to change the JSONata expression to:
`{"isUnderThreshold": (serialNumber ~> $replace(/^\w*-?0*/, '') ~> $number()) < 5000}`
