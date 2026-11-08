`prefer-to-be` considers `RegExp` literal notation as a literal
The [literal notation](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/RegExp#literal_notation_and_constructor) of a regular expression in JavaScript is still a `RegExp` object. But The `prefer-to-be` rule treats literal notation as a literal. So it auto-fixes `.toStrictEqual` into `.toBe`, causing tests to fail.

For example, given two tests that pass:

```ts
it('is an example', () => {
  const token: RegExp = new RegExp('[abc]+', 'gu');

  expect(token).toStrictEqual(/[abc]+/gu);
  expect(token).toStrictEqual(new RegExp('[abc]+', 'gu'));
});
```

Is changed into:

```ts
it('is an example', () => {
  const token: RegExp = new RegExp('[abc]+', 'gu');

  expect(token).toBe(/[abc]+/gu);
  expect(token).toStrictEqual(new RegExp('[abc]+', 'gu'));
});
```

And the `.toBe` test fails
