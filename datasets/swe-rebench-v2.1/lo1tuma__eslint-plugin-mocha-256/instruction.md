`no-setup-in-describe` triggers on `describe.skip`
```js
describe.skip( 'My test', () => {
  it( 'Something', () => {
    // Foo
  } );
} );
```

This should not trigger `no-setup-in-describe`, yet it does.

This can be worked around by moving the `skip` to each of the `it` calls.
