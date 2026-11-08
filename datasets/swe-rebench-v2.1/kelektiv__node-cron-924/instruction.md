`waitForCompletion` not working as expected
### Description

In my testing I can't get `waitForCompletion` to stop another instance of a job running concurrently as expected based on changes made and documented in 3.3.0.

### Expected Behavior

`waitForCompletion` should stop multiple instances running concurrently, as documented.

### Actual Behavior

Setting `waitForCompletion` true or false doesn't seem to make any difference.

### Possible Fix

_No response_

### Steps to Reproduce

``` js
import { CronJob } from "cron";
let c = 0;
CronJob.from({
  cronTime: "*/1 * * * * *",
  onTick: async () => {
    console.log(++c);
    await new Promise((r) => setTimeout(r, 1100));
    c--;
  },
  waitForCompletion: true,
  start: true,
});
```

# Output
```
1
2
2
...
```

# Expect
```
1
1
1
...
```

### Context

I had previously implemented my own solution to stop multiple instances of a job running concurrently. I thought with 3.3.0 I could simplify my code and instead use the new feature provided by `cron`.

### Your Environment

- **`cron` version**: 3.3.0
- **NodeJS version**: 22.12.0
- **Operating System and version**: Windows 11 Pro
