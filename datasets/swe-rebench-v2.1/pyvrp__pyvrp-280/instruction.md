Should we collect statistics by default?
Issues based on the other PR linked from below [@leonlan]. Right now we do not collect statistics by default, citing performance reasons. Have we actually checked whether it matters? If it doesn't I think we should collect statistics by default, since they are useful to have.

### Benchmarks

Current main (698a9d70eea87ad35c1a9e0df533896169c2aa52; job ID 3067936; 10x seeds/1h with `configs/vrptw.toml`; no stats):
```
 Avg. objective: 333402.8 (min: 333220, max: 333486)
Avg. iterations: 86955.2 (min: 67928, max: 97156)
```
Current main (fe6c756f0ef981a9efe39f8cc17306b667744ebf; job ID 3069860; 10x seeds/1h with `configs/vrptw.toml`; stats):
```
 Avg. objective: 333414.6 (min: 333218, max: 333644)
Avg. iterations: 83515.8 (min: 68249, max: 94540)
```

### Additional contract requirements

The benchmark results above show comparable objectives and iteration counts with and without statistics collection, so statistics must be collected by default during genetic-algorithm runs. An explicit caller opt-out may remain available, but ordinary runs using default options must collect statistics.
