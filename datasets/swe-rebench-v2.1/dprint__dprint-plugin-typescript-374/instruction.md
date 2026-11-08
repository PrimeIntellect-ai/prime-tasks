Parsing error for .js file with jsx contents
**Describe the bug**

dprint-plugin-typescript version: 0.68.3

**Input Code**

```js
const Template = args => <CurrencyInput {...args[0]} />;
```

**Expected Output**

```js
const Template = args => <CurrencyInput {...args[0]} />;
```

**Actual Output**

```ts
Line 1, column 26: Expression expected

   Template = args => <CurrencyIn
                      ~

Line 1, column 41: Expected a semicolon

  s => <CurrencyInput {...args[0]
                      ~
```

This only happens when the file ends with `.js` instead of `.jsx` (works for `ts` and `tsx`)
