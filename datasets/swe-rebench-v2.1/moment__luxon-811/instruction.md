Adding 0 units (Say milliseconds) makes a duration compare non equal
I think this should be a bug, although I accept there might be an argument I haven't considered.

Given this simple testcase I would consider the two values to compare as equal.

```typescript

import { DateTime, Duration } from 'luxon';

function main() {

    const testoffset= Duration.fromISO("P1W");
    const testzero  = Duration.fromMillis(0);

    const same_offset = testoffset.plus(testzero)

    console.assert(testoffset.equals(same_offset),
                    "Aren't these logically the same");

};

main();
```

But have I missed something ?
