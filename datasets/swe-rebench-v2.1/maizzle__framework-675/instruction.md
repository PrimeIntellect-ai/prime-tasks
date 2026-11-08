Six-digit HEX transformer applies to text content
- Maizzle Version: 3.7.3
- Node.js Version: 15.14.0

The [Six-digit HEX](https://maizzle.com/docs/code-cleanup/#six-digit-hex) transformer erroneously applies to text content inside HTML. For example, inside a template, the following content:

```
<h1>Welcome to issue #123 or our newsletter!</h1>
```

…is turned into:

```
<h1>Welcome to issue #112233 or our newsletter!</h1>
```

Setting `sixHex:false` in the config solves this (but turns this off which might be unfortunate for those who need it).
