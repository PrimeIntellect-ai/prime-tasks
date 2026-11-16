Rule Change: (valid-typeof) undefined should be banned
### What rule do you want to change?

valid-typeof

### What change to do you want to make?

Generate more warnings

### How do you think the change should be implemented?

A new default behavior

### Example code

```js
typeof foo === null
typeof foo === undefined
```


### What does the rule currently do for this code?

only `null` is reported

### What will the rule do after it's changed?

both `null` and `undefined` should be reported

### Participation

- [X] I am willing to submit a pull request to implement this change.

### Additional comments

_No response_

### Additional contract requirements

- In the default configuration of `valid-typeof`, a comparison of a `typeof` expression with the unquoted identifier `undefined` (for example `typeof foo === undefined`, `undefined === typeof foo`, or `typeof bar !== undefined` inside an `if`) must be reported with the same message as other invalid typeof comparison values, and the report must point at the `undefined` operand.
- Comparisons of a `typeof` expression with `null` continue to be reported as they are today.
