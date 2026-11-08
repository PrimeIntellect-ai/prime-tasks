naming for iterations and/or duration
Working through writing a few sample benchmarks, I was exploring `Benchmark.defaultConfiguration.desiredIterations`, `Benchmark.defaultConfiguration.desiredDuration`, and how they relate to each other.

I do think the names could be improved by renaming them to `maxIterations` and `maxDuration`, respectively. I'm also thinking that as we cobble the documentation, expanding on `Benchmark.Configuration` (and maybe the article `WritingBenchmarks.md`), it would be worth calling out specifically that the running will go until the first of these two are hit.

And just to double check - if you specify warmupIterations on the configuration, does that take place before either the iterations vs. duration markers are measured?

### Additional contract requirements

Configured warmup iterations are completed before measurement begins. They do not count toward `maxIterations`, and the `maxDuration` measurement interval begins after warmup. Once measurement has started, the benchmark stops when either `maxIterations` or `maxDuration` is reached, whichever happens first.
