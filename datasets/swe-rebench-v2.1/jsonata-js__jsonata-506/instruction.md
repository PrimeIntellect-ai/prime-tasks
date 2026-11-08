Proposal:  Add short-circuit evaluation for conditionals
Consider the following input:
`{"foo":""}`
and the following JSONata expression:
`foo != "" and $number(foo) > 0`
If short-circuit conditionals existed in JSONata, then the result would be `false`.  However, because these do not exist in JSONata, the following error is produced:
`Unable to cast value to a number: ""`

However, currently a work around is possible with `foo != "" ? $number(foo) > 0 : false`
