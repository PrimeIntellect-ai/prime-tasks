Proposal: Add "always-multiline" option to "multiline-ternary" rule
**What rule do you want to change?**

[multiline-ternary](http://eslint.org/docs/rules/multiline-ternary)

**Does this change cause the rule to produce more or fewer warnings?**

n/a

**How will the change be implemented? (New option, new default behavior, etc.)?**

new option (`always-multiline`)

**Please provide some example code that this change will affect:**

```js
// 1
var foo = bar > baz ? value1 : value2;

// 2
var foo = bar > baz ?
    value1 : value2;
```

**What does the rule currently do for this code?**

##### `never`

1 - nothing (already correct)
2 - requires the second line to be moved onto the end of the first line

##### `always`

1 - requires `value1` and `value2` to each be moved onto their own line
2 - requires `value2` to be moved onto the next line

**What will the rule do after it's changed?**

##### `always-multiline`

1 - nothing (already correct)
2 - requires `value2` to be moved onto the next line

`always-multiline` is the same as `always` except it allows ternary expressions to be on a single line
(so the `always` functionality is enforced only if there is a newline somewhere within the ternary expression).
