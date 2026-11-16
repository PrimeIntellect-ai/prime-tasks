Add `Else.s` simple constructor that accepts only 1 `Conditional`
### Motivation

https://github.com/intel/rohd/pull/210 implements `If.s`, `Iff.s`, and `ElseIf.s`, but not `Else.s`.

### Desired solution

It would be nice to also add `Else.s` for completeness.

### Alternatives considered

_No response_

### Additional details

_No response_

### Additional contract requirements

`Else.s` accepts one `Conditional` and acts as an else branch in an `IfBlock`: the conditional is executed only when every preceding branch condition is false.
