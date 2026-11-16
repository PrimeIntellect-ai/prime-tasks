Side effects in conditions are not detected
The next code throws a no-side-effects error:

```
foo: computed(function() {
  this.set('bar', 'someValue');
})
```

Yet this code doesn't:

```
foo: computed(function() {
  const condition = true;
  if (condition) {
    this.set('bar', 'someValue');
  }
})
```
