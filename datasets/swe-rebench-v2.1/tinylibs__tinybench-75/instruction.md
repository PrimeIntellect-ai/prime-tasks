Concurrent benchmarking
I was hoping to do some testing of how JS frameworks perform when getting multiple requests at a time. A concurrency limit flag would be dope.

Did some reading of [past issues](https://github.com/tinylibs/tinybench/issues/21) and I don't fully agree with the removal of the previous parallel options. Surely it won't be perfectly accurate, but no benchmark is

### Additional contract requirements

Expose `Bench.runConcurrently(limit?: number)` to run all registered benchmark tasks concurrently. When provided, `limit` is the maximum number of tasks executing at the same time; when omitted, there is no concurrency cap.
