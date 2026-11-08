`no-empty-description` incorrectly flags non-empty descriptions.
The following seem like reasonable test descriptions, but they get flagged by `no-empty-description`:

```js
describe('eslint-plugin-mocha', function() {
  const description = 'description';
  it(description, function() {});

  ['test1', 'test2'].forEach(testname => {
    it(testname, function() {});
  });

  const removePrefix = 'testcase.prefix';
  it(removePrefix.replace('.prefix'), function() {});
});
```

```
   3:3  error  Unexpected empty test description  mocha/no-empty-description
   6:5  error  Unexpected empty test description  mocha/no-empty-description
  10:3  error  Unexpected empty test description  mocha/no-empty-description
```

Was this intended with #304?
