Boolean operators return inconsistent results with undefined inputs
This issue was first raised in a [Slack post](https://jsonata.slack.com/messages/C2L3MR5EH/p1531168044000184). I'm reposting here (with some additional info) so it doesn't get lost.

The original poster was using the `or` operator with one falsy value and one undefined value (a non-existent path expression). They noticed that the `or` operator sometimes returned `false` and sometimes returned `undefined` depending on the order of the operands.

I tried various combinations of the `or` and `and` operators with one or more undefined values (named `foo` and `bar`) and got the following results.

#### Or

```
true or foo    // true
foo or true    // true

false or foo   // undefined
foo or false   // false

foo or bar     // undefined
```

#### And

```
true and foo    // undefined
foo and true    // undefined

false and foo   // false
foo and false   // undefined

foo and bar     // undefined
```

Note that:

1. Combining a falsy value with an undefined value does indeed give different results depending on the order of the operands.

2. There's a mix of boolean and undefined results, e.g. `true or foo` returns `true` but `true and foo` returns `undefined`.

These are the only binary operations that produce such inconsistent results. Numeric operators (like `+` and `-`) return `undefined` if either operand is undefined. Comparison operators (like `=` and  `<`) return `false` if either operand is undefined. And the concatenation operator (`&`) treats undefined operands as empty strings.

Boolean operators should have a similarly well-defined approach to undefined inputs. I suggest one of the following:

1. Treat undefined operands as `false` (this would turn all of the `undefined` results above to `false`).

2. Return `undefined` if either operand is undefined (all of the above expressions would then evaluate to `undefined`).

Any thoughts on this, @andrew-coleman?

### Additional contract requirements

- Boolean operators must treat undefined operands as false. For example, `false or foo` evaluates to `false`.
