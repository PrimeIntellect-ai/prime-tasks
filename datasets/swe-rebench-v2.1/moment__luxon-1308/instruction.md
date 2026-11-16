Interval#count incorrectly includes the end-point
**Describe the bug**
The Interval documentation states that
> An Interval object represents a **half-open** interval of time

To me this means that the interval includes the starting point, but not the end point. This is confirmed by checking `interval.contains(interval.end)`, which always returns false. However `Interval#count` also counts the endpoint.

**To Reproduce**
```js
const {Interval, DateTime} = require('luxon');

const startDate = DateTime.fromISO("2022-10-01T00:00:00.000+02:00");
const interval = Interval.after(startDate, {days: 2});

console.log(interval.contains(interval.end)); // as expected this is false
console.log(interval.count('days')); // this reports 3, but the interval only contains 2 calendar days (1st and 2nd)
console.log(interval.length('hours')); // as expected this reports exactly 48, because the first millisecond of the 3rd is not included
```

See here: https://runkit.com/embed/xxwq2ofg22di

**Actual vs Expected behavior**
`Interval#count` should not count the interval's endpoint.

**Desktop (please complete the following information):**

- OS: Linux Mint
- Browser: Chrome 106, also happens on Node 14
- Luxon version: 3.0.4
- Your timezone: Europe/Berlin

**Additional context**
Looking at the code for `count`, it unconditionally adds 1 to the result of diffing start and end. [HIDDEN]
