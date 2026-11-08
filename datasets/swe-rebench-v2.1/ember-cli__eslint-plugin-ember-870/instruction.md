False positive with `require-computed-macros` rule using `this.` for filterBy/mapBy value
This example should not use the `filterBy` macro because `this.token` needs to remain inside a function:

```js
myProp: computed('items.@each.token', 'token', function () {
  return this.items.filterBy('token', this.token);
}),
```

### Additional contract requirements

When a `filterBy` or `mapBy` call inside a computed property getter has an argument that depends on the getter's surrounding `this`, do not recommend replacing the call with a computed macro; that value must remain inside the function.
