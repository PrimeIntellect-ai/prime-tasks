strict Struct with additional methods throws a TypeError on updating
Test case:

```javascript
const t = require('tcomb');

const Rectangle = t.struct({
  width: t.Number,
  height: t.Number
}, {strict: true});

Rectangle.prototype.getArea = function () {
  return this.width * this.height;
};

let r = Rectangle({width: 10, height: 10});
Rectangle.update(r, {width: {$set: 20}});
```
throws:
```
TypeError: [tcomb] Invalid additional prop "getArea" supplied to Struct{width: Number, height: Number}
```

[HIDDEN]

### Additional contract requirements

- Updating a strict Struct instance that has an added prototype method with a valid field patch must succeed; the inherited method must not be treated as an additional supplied property. In the example, the updated instance has `width` equal to 20.
