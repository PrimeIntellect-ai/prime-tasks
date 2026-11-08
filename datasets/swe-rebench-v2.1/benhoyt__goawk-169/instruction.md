Add optimization for a[1] -> a["1"]
Based on conversation in https://github.com/benhoyt/goawk/pull/154#discussion_r995566431, I realized we (c|sh)ould actually make GoAWK do this micro-optimization: whenever it sees "array indexed by constant integer" like `a[1]` it could convert that to `a["1"]` for a slight speedup (though we should verify that it's actually faster!).

### Additional contract requirements

- When printing annotated source for coverage instrumentation, render coverage-array indices as integer literals, such as `__COVER[1]`, rather than quoted strings such as `__COVER["1"]`.
