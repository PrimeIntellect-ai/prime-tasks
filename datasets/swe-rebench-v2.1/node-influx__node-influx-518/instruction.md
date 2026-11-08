INanoDate.toISOString can produce an incorrectly rounded timestamp
## Expected Behavior
`INanoDate.toISOString()` should return the correct ISO 8601 string with millisecond precision.

## Actual Behavior
`INanoDate.toISOString()` has a rounding error that produces an ISO 8601 that is off by 1 millisecond in some situations.

## Steps/Code to Reproduce the Problem
The following code sample demonstrates the problem:
```
import { toNanoDate } from 'influx';

// This is a nanosecond "precision" string timestamp with no significant nanosecond digits
const date = new Date('2019-05-30T08:55:41.002Z');
const nanoTimestamp = `${date.getTime()}000000`;

// Generate the INanoDate
const result = toNanoDate(nanoTimestamp);

// Despite no nanoseconds, so there should be no rounding the significant millisecond is rounded down
console.log(result.toISOString() === '2019-05-30T08:55:41.001Z');

// The nanosecond timestamp is, however, correct
console.log(result.toNanoISOString() === '2019-05-30T08:55:41.002000000Z');
```

The timestamp is correct in cases where there are 10s of significant milliseconds. So, I suspect the bug is due to an erroneous call to Math.floor or something in the rounding logic for producing the truncated timestamp.

## Specifications

  - Version: 5.5.1
  - Platform: Ubuntu 19.04
