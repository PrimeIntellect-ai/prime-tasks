Show symbol for char-code nodes
For HEX, Octal, Decimal, and Unicode char codes we can show also an actual symbol corresponding to the code:

```
\u003B
```

Currently produces:

```js
{
  "type": "Char",
  "value": "\\u003B",
  "kind": "unicode"
}
```

We should add `symbol` property to the node:

```js
{
  "type": "Char",
  "value": "\\u003B",
  "kind": "unicode",
  "symbol": ";"
}
```
