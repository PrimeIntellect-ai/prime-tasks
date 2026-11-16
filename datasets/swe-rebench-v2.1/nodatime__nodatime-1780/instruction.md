Use Int128 in .NET 8 target
(e.g. for Duration.ToInt128Nanoseconds etc)

We could *experiment* with a conditional implementation, using Int128 in Duration when it's available - but I suspect it'll be too fiddly.

### Additional contract requirements

- Provide `Duration.FromNanoseconds(Int128 nanoseconds)` to create a duration from an Int128 nanosecond count. It must preserve counts within the supported range, from `Duration.MinNanoseconds` through `Duration.MaxNanoseconds`, and throw `ArgumentOutOfRangeException` for counts outside that range.
