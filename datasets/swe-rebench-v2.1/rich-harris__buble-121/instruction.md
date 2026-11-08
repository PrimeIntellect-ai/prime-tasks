Loops create redundant "this" variables
Using `this` keyword inside a loop creates redundant variables that aren't necessary because loops don't create closures (`this` inside a loop should always point to the same object as outside).

[Minimal example](https://buble.surge.sh/#function%20bar()%20%7B%0A%20%20while%20(true)%20this%3B%0A%7D):

```js
function bar() {
  while (true) this;
}
```

Produces:

```js
function bar() {
  var this$1 = this;

  while (true) { this$1; }
}
```

Expected output:

```js
function bar() {
  while (true) { this; }
}
```

Same behavior for `for` and `do ... while` loops. Looks like a bug to me — a harmless one in practice, but quite unpleasant for perfectionists like me. :)
