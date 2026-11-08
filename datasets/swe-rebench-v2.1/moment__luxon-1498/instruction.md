shiftAll() regression
**Describe the bug**
What used to be `P99Y11M3W2DT10H29M6S` in v3.3.0 is now `P99Y11M3.3481250000000005W` in v3.4.2

**To Reproduce**
```ts
const { DateTime, Duration } = require("luxon@3.4.2");

const purchaseDate = DateTime.fromObject(
  { day: 1, month: 1, year: 2020 },
  { zone: "UTC", conversionAccuracy: "longterm" }
);
const warranty = Duration.fromObject({ years: 100 }, { zone: "UTC", conversionAccuracy: "longterm" });
const now = DateTime.fromObject(
  { day: 8, month: 1, year: 2020 },
  { zone: "UTC", conversionAccuracy: "longterm" }
);
const age = now.diff(purchaseDate).shiftToAll();
const warrantyLeft = warranty.minus(age).shiftToAll();

console.log({
  warrantyLeft: warrantyLeft.toString(),
});
```
You can run it on https://npm.runkit.com/luxon and see the unexpected `{warrantyLeft: "P99Y11M3.3481250000000005W"}` in the output.

**Actual vs Expected behavior**
```ts
const { DateTime, Duration } = require("luxon@3.3.0");

const purchaseDate = DateTime.fromObject(
  { day: 1, month: 1, year: 2020 },
  { zone: "UTC", conversionAccuracy: "longterm" }
);
const warranty = Duration.fromObject({ years: 100 }, { zone: "UTC", conversionAccuracy: "longterm" });
const now = DateTime.fromObject(
  { day: 8, month: 1, year: 2020 },
  { zone: "UTC", conversionAccuracy: "longterm" }
);
const age = now.diff(purchaseDate).shiftToAll();
const warrantyLeft = warranty.minus(age).shiftToAll();

console.log({
  warrantyLeft: warrantyLeft.toString(),
});
```
You can run it on https://npm.runkit.com/luxon and see the expected `{warrantyLeft: "P99Y11M3W2DT10H29M6S"}` in the output.

**Desktop (please complete the following information):**

- OS: WSL2 in Windows
- Browser N/A
- Luxon version 3.4.2
- Your timezone Australia/Sydney

**Additional context**
Might be loosely related to https://github.com/moment/luxon/issues/1482 ?
