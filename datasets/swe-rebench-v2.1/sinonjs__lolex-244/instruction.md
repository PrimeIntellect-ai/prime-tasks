Support hrtime.bigint()
> We understand you have a problem and are in a hurry, but please provide us with some info to make it much more likely for your issue to be understood, worked on and resolved quickly.


* Lolex version : 3.1.0
* Environment   : Node.js 10.15.3
* Example URL   : N/A
* Other libraries you are using:

**What did you expect to happen?**

My code uses [`process.hrtime.bigint()`](https://nodejs.org/api/process.html#process_process_hrtime_bigint). When stubbing `process.hrtime` using Lolex, this method is no longer available.

On platforms that don't provide this function, I'd expect it not be made available by Lolex either.

**What actually happens**

It returns the stubbed time, as a BigInt.

**How to reproduce**
> Describe *with code* how to reproduce the faulty behaviour
> or link to code on JSBin or similar

```console
$ node                                                                                                                                            > process.hrtime.bigint()
39069092115824n
> require('lolex').install({toFake: ['hrtime']})
{ now: 0, … }
> process.hrtime.bigint()
TypeError: process.hrtime.bigint is not a function
```

### Additional contract requirements

- The clock exposes a `bigint()` method on its `hrtime` function: `clock.hrtime.bigint()` takes no arguments and returns the elapsed nanoseconds since the clock started, as a BigInt.
- The returned value advances with the clock's simulated time (for example via `clock.tick`, `clock.runAll`, or scheduled timers) and is unaffected by `clock.setSystemTime`.
- When the environment does not provide a native `process.hrtime.bigint`, the clock does not make `clock.hrtime.bigint` available.
