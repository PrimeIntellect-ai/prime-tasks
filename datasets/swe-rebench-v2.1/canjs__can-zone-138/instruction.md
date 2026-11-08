Allow taking an Array in the constructor argument
Instead of having to do:

```js
new Zone({
  plugins: [...]
});
```

This would be nice if you're only using plugins:

```js
new Zone([
  ...
]);
```
