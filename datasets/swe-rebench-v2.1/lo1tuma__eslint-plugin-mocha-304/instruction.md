Rule proposal: no-empty-description
Hi, that's would be awesome to catch empty suites/tests.

```js
test('', function () {
    assert.equal(2 + 2, 4);
});
```

Of course, I can use `valid-suite-description`/ `valid-test-description` rules to enforce descriptions format, but I don't have a specific convention, and a lightweight `no-empty` rule will be useful for such a case.

I'm ready to provide help with implementation, if needed.

### Additional contract requirements

- The rule is named `no-empty-description`.
- By default, the rule applies to calls named `describe`, `context`, `suite`, `it`, and `test`.
- The rule accepts an options object with `testNames` (an array of call names to treat as tests) and `message` (the diagnostic text to use for violations); for example, `testNames: [ 'someFunction' ]` makes `someFunction(...)` calls subject to the rule.
- When no `message` option is supplied, report violations with the exact message `Unexpected empty test description.`
- A description that is missing, an empty string, or only whitespace is empty.
- Report each violation at the starting position of the test call expression.
