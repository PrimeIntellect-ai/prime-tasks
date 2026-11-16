DateTime.fromFormat fails in some cases when running Node 18.13.0
**Describe the bug**
I Node 18.13.0 parsing DateTime using the fromFormat method can in some cases fail parsing, where running in previous Node version it would not.

**To Reproduce**

```js
const { DateTime } = require("luxon");

const format = "M/d/yyyy tt";
const dateTimeString = "1/17/2023 11:00:00 PM";

const dateTime = DateTime.fromFormat(dateTimeString, format);

console.log(dateTime.isValid);
// "false" when running in 18.13.0
// "true" when running in 18.12.0

console.log(dateTime.toISO());
// "null" when running in 18.13.0
// "2023-01-17T23:00:00.000+01:00" when running in 18.12.0
```


**Actual vs Expected behavior**
I would expect the outcome of running the snippet to be the same in 18.12.0 and 18.13.0 and that the parsed DateTime is valid.
Instead in 18.12.0 the DateTime is correctly parsed while in 18.13.0 it is invalid.


**Desktop (please complete the following information):**

- OS: Windows 11 (but originally noticed noticed in debian based docker container)
- Browser: Node 18.13.0
- Luxon version: 3.2.1
- Your timezone: Europe/Copenhagen

**Additional context**
Add any other context about the problem here.

### Additional contract requirements

When parsing a localized macro token, the whitespace between the time and meridiem may be supplied as either an ordinary space or the non-breaking whitespace rendered by the locale. Both forms must parse to the same date and time.
