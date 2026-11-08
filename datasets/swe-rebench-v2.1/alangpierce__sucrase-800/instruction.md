Constructor return type annotations produce invalid JS syntax
Source:
```js
class Foo {
  constructor(): Foo {
    return this;
  }
}
```

Transformed (actual):
```js
class Foo {
  constructor():  {
    return this;
  }
}
```

Transformed (expected):
```js
class Foo {
  constructor()  {
    return this;
  }
}
```

Reproductions:
- TS: https://sucrase.io/#transforms=typescript&code=class%20Foo%20%7B%0A%20%20constructor()%3A%20Foo%20%7B%0A%20%20%20%20return%20this%3B%0A%20%20%7D%0A%7D
- Flow: https://sucrase.io/#transforms=flow&code=class%20Foo%20%7B%0A%20%20constructor()%3A%20Foo%20%7B%0A%20%20%20%20return%20this%3B%0A%20%20%7D%0A%7D
