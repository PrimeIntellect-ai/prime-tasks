Auto flush when process is exiting
Currently, you need to be careful to call `metrics.flush()` before your app quits (since you may have accumulated more metrics since the most recent flush). If auto-flushing is on, it would be nice to also flush automatically during the `beforeExit` event in Node.js (and Bun and Deno, although I’m not sure if we are actually compatible with those right now).
