`retryTimes` in `@lib/util/async` is broken
Noticed this while working on something else. Because we use an interval, it is possible that for long-running async function calls, it'll start a new try before the old try has completed. [HIDDEN]
