RFC: Relax `isObject` contraint in interface combinator
```js
import t from 'tcomb'

const ToStringable = t.interface({
  toString: t.Function
})

console.log(ToStringable.is(1)) // => false, should be true
```

- https://github.com/gcanti/tcomb/blob/master/lib/interface.js#L55
- https://github.com/gcanti/tcomb/blob/master/lib/interface.js#L97

/cc @ctrlplusb @giogonzo

### Additional contract requirements

- The interface combinator is exposed as `t.inter` (an alias of `t.interface`).
- The interface type exposes a static `is(value)` method that returns a boolean.


- For an interface defined by `{x: t.Number, y: t.Number}`, calling it with `{}` must throw the exact message `[tcomb] Invalid value undefined supplied to {x: Number, y: Number}/x: Number`.
