error handling
Hello.

Is there a way to catch an error during the cronjob execution? As I see cron.start() doesn't return promise, so we can't just hang a .catch() there.

I guess it's common need so some people found a good approach to solve it.

Thank you a lot!

**Feature specification: https://github.com/kelektiv/node-cron/issues/426#issuecomment-1741837777**

### Additional contract requirements

When creating a job with `CronJob.from`, callers can supply an optional `errorHandler` callback. Whenever the job's `onTick` callback throws, the error handler receives that thrown error, allowing application code to handle it; this applies on every execution that throws.
