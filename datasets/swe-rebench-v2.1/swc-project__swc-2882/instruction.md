Arrow function in constructor will generate invalid code
### Describe the bug

This is a bit of trick because if class transform is involved everything works fine, but there exist some browsers like `chrome 46` which support class but not arrow

### Input code

```typescript
class Foo extends function() {
} {
    constructor(){
        var _this = this;
        var foo = function() {
            return _this;
        };
        if (true) {
            console.log(super(), foo());
        } else {
            super();
            console.log(foo());
        }
    }
}
```


### Config

```js
{
  jsc: {
    parser: {
      syntax: "ecmascript"
    }
  },
  env: {
    targets: {
      chrome: "46"
    },
    mode: "entry",
    coreJs: 3
  }
}
```


### Playground link

_No response_

### Expected behavior

babel would generate
```js
class Foo extends function () {} {
  constructor() {
    var _this;

    var foo = function foo() {
      return _this;
    };

    if (true) {
      console.log((super(), (_this = this)), foo());
    } else {
      super();
      _this = this;
      console.log(foo());
    }
  }
}
```
which works fine, while swc will output something like
```js
class A {
  constructor() {
    var _this = this
  }
}
```

### Version

1.2.111

### Additional context

_No response_
