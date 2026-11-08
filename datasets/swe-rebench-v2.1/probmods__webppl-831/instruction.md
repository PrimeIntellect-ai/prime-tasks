The result of evaluating a conditional expression can't be called directly
This works:

```js
var f = (true ? idF : idF);
f(0);
```

This doesn't:

```js
var x = (true ? idF : idF)(0);
x;
// => Syntax error: isPrimitive doesn't handle node
// On webppl: v0.9.6-a3fae91
```
