`removeNullAttributes` circumvents null checks for required fields
If you mark a field as `required: true` or `required: 'always'`, the `removeNullAttributes` config can still result in null values for that field. You can get dynamodb-toolbox to insert a null value by passing it an empty string or a whitespace-only value and getting it to coerce to `null` under the hood. In this case, the db will remove the attribute without complaint, effectively circumventing the null checks for that field. This even occurs if you set `required` to `'always'` instead of `true`.

Here's an example of a unit test that would fail currently:
```
  it('fails when given a null-like value for an \'always\' required field', () => {
    expect(() => TestEntity3.updateParams({
      'pk': 'test-pk',
      'test2': '',
    })).toThrow(`'test2' is a required field`)
  })
````


This fails with:
```
  - update › fails when given a null-like value for an 'always' required field
    Expected substring: "'test2' is a required field"
    Received function did not throw
```

The resulting behavior is that the key `test2` gets removed from the db, and the application will probably crash because it's expecting to always get a non-null value out of dynamo.

This is related to #252, but would be a separate fix.
