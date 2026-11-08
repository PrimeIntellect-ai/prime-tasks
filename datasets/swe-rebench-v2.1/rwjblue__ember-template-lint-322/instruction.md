support plugins extending other plugins
The main use case is to have a plugin extend base `recommended` so you don't have to do `extends: ['recommended', 'plugin1:recommended'],` yourself. I tried inside of a plugin:

```js
configurations: {
  recommended: {
    extends: 'recommended',
    rules: {
    }
  }
}
```

but it didn't work.
