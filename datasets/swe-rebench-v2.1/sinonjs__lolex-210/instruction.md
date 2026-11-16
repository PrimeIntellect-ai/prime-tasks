High-resolution timer gets tripped up by floating point arithmetic
* Lolex version : 2.7.4

**What did you expect to happen?**

Advancing the clock with fractional milliseconds should give me an integer nanosecond value when I call `process.hrtime(prev)`.

**What actually happens**

The nanosecond value is a float, not an integer.

**How to reproduce**

```js
const clock = lolex.install()
clock.tick(1022.7791)
clock.hrtime([0, 20000000]) // [ 1, 2779099.999999881 ]
```

The reproduction advanced the clock by a fraction of a nanosecond. I suppose it'd be fine to round the computed nanosecond value, but I'm not sure if it should be rounded up or down. Alternatively something like https://www.npmjs.com/package/decimal.js may help to avoid the floating point arithmetic. Perhaps `tick()` should round down to the closest nanosecond, but I'm not sure if that'll help or not.
