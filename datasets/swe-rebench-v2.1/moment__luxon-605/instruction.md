Duration toISO produces invalid ISO string
Hey 👋

There's some floating point madness going on that makes Duration produce invalid ISO strings. See example below.

```js
const duration = Duration.fromObject({seconds: 17, milliseconds: 548});
const isoString = duration.toISO() // -> "PT2M17.548000000000002S"
const parsedDuration = Duration.fromISO(isoString);
console.log(parsedDuration.isValid); // -> false
```
