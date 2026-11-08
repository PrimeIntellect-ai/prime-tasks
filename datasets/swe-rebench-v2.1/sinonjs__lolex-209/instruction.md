reset() does not reset high-resolution timer
* Lolex version : 2.7.4

**What did you expect to happen?**

`reset()` resets the high-resolution timer.

**What actually happens**

The high-resolution timer is not reset.

**How to reproduce**

```js
const clock = lolex.install()
clock.now === 0
clock.tick(20)
clock.hrNow === 20
clock.reset()
clock.now === 0
clock.hrNow === 20
```
