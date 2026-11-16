Interface filters additional props when props contain a struct
Version: 3.2.11

As per documentation, an `interface` should not filter additional props unless `strict = true`. However, when an interface contains a `struct` member (or, I believe, when there are non-identity types), additional props do get filtered out.

Here's a minimal console.log test:

```javascript
const t = require('tcomb')

const Point = t.struct({
  x: t.Number,
  y: t.Number
})

const PointInterface = t.inter({
  x: t.Number,
  y: t.Number
})

const HydrateInterface = t.inter({
  point: Point
})


console.log(PointInterface({
  x: 1,
  y: 2,
  extra: 3
}))

// Expected:
// { x: 1, y: 2, extra: 3 }
//
// Output (correct):
// { x: 1, y: 2, extra: 3 }


console.log(HydrateInterface({
  point: { x: 1, y: 2 },
  extra: 3
}))

// Expected:
// { point: Struct { x: 1, y: 2 }, extra: 3 }
//
// Output (incorrect):
// { point: Struct { x: 1, y: 2 } }
//
// The additional prop "extra" should not be filtered out
```
