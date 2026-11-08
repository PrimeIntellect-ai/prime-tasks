Bug: sort-interfaces changes overload ordering for constructors
### Describe the bug

`sort-interfaces`  changes overload ordering of constructor in interfaces, which can cause existing code to break.

Method overloads do not change order, so constructors should not change too.

### Code example

```
interface Interface {
  new (value: number | string): number;
  new (value: number): unknown;
}
```

### ESLint version

latest

### ESLint Plugin Perfectionist version

latest

### Additional comments

I have written the following test to verify the issue in this repo.
The case with `new` clause fails, while other cases pass.

```js
ruleTester.run(`${ruleName}(${type}): sorts interface overloads`, rule, {
  invalid: [
    {
      errors: [
        {
          data: {
            right: 'method',
            left: 'methodA',
          },
          messageId: 'unexpectedInterfacePropertiesOrder',
        },
      ],
      output: dedent`
        interface Interface {
          method(value: number | string): number;
          method(value: number): unknown;

          methodA(value: number | string): number;
          methodA(value: number): unknown;
        }
      `,
      code: dedent`
        interface Interface {
          methodA(value: number | string): number;
          methodA(value: number): unknown;

          method(value: number | string): number;
          method(value: number): unknown;
        }
      `,
      options: [options],
    },
  ],
  valid: [
    {
       code: dedent`
         interface Interface {
           method(value: number | string): number;
           method(value: number): unknown;
         }
       `,
       options: [options],
     },
     {
       code: dedent`
         interface Interface {
           new (value: number | string): number;
           new (value: number): unknown;
         }
       `,
       options: [options],
     },
   ],
})
```

### Validations

- [X] Read the [docs](https://perfectionist.dev).
- [X] Check that there isn't [already an issue](https://github.com/azat-io/eslint-plugin-perfectionist/issues) that reports the same bug to avoid creating a duplicate.
