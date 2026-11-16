Bug: sort-enums negative values not sorted correctly with forceNumericSort: true
### Describe the bug

In the sort-enums rule when the forceNumericSort: true flag is set a negative value causes the ordering to fallback on the configured type (alphabetical etc.)



### Code example

```typescript
export enum NumericTypeCorrectOrder {
    One = 1,
    Two = 2,
    Three = 3
}

export enum NumericTypeWrongOrder {
    One = 1,
    OneNegative = -1,
    Three = 3,
    Two = 2
}

```

### ESLint version

v9.15.0

### ESLint Plugin Perfectionist version

v4.0.3

### Additional comments

The sort-enums.ts source code has a check for determining an enum is a numeric one ([HIDDEN])

```typescript
     let isNumericEnum = members.every(
        member =>
          [HIDDEN]
      )
```

[HIDDEN]

### Validations

- [X] Read the [docs](https://perfectionist.dev).
- [X] Check that there isn't [already an issue](https://github.com/azat-io/eslint-plugin-perfectionist/issues) that reports the same bug to avoid creating a duplicate.

### Additional contract requirements

- With `forceNumericSort: true`, enum members whose initializer is a numeric constant expression must be sorted numerically together with the other numeric members, instead of falling back to the configured `type`. A numeric constant expression is a numeric literal, a unary `+`, `-` or `~` applied to a numeric constant expression, or a binary `+`, `-`, `*`, `/`, `%`, `**`, `<<`, `>>`, `&`, `|` or `^` applied to two numeric constant expressions.
- When enum members are out of order, the rule reports an `unexpectedEnumsOrder` error whose data identifies the `left` and `right` members.
