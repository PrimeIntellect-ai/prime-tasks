Job scheduled with setTime throws error instead of running
### Description

When I reschedule a job to a specific date using the `job.setTime(new CronTime(startDate))` function, the job throws an error at the scheduled time instead of executing.

### Expected Behavior

I expect the job to run at `startDate`.

### Actual Behavior

I'm getting the following error:

```
node_modules/cron/dist/time.js:93
                throw new Error('WARNING: Date in past. Will never be fired.');
                ^

Error: WARNING: Date in past. Will never be fired.
```

### Possible Fix

_No response_

### Steps to Reproduce

```
// create job with a default schedule
const job = new CronJob(
  '0 0 20 * * *',
  () => console.log('onTick')
)

// re-schedule for 5 seconds from now
const startDate = new Date(Date.now() + 5000)
job.setTime(new CronTime(startDate))
job.start()

console.log('current date:', new Date())
console.log('start date:', startDate)
```

### Context

This used to be working properly in earlier versions of the library.

### Your Environment

- **`cron` version**: 3.1.3
- **NodeJS version**: 20.8.1
- **Operating System and version**: macOS 14.0, Debian 10.13
