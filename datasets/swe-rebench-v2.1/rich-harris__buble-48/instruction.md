[bug] `q.a = class {}` resolves to undefined
Here is an [example](http://buble.surge.sh/#const%20q%20%3D%20%7B%7D%3B%0A%0Aq.a%20%3D%20class%20%7B%0A%20%20c%20()%20%7B%7D%0A%7D).

---

input

```js

const q = {};

q.a = class {
  c () {}
}

```

output

```js

var q = {};

q.a = (function () {
  function undefined () {}

  undefined.prototype.c = function c () {};

  return undefined;
}())

```

---

This way it is working fine.

```js

const q = {};

Object.assign(q, {a: class {
	c () {}
}})

```

### Additional contract requirements

The anonymous class expression assigned to a property must be named after
that property, so that the emitted constructor is named `a` rather than
`undefined`. For the input above, the fixed output must be exactly:

```js

var q = {};

q.a = (function () {
  function a () {}

  a.prototype.c = function c () {};

  return a;
}())

```
