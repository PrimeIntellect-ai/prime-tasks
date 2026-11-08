Feature: Custom benchmark tags
I want to test the waters on whether the community would be receptive to a PR that adds the ability to apply custom tags to a benchmark.
This specifically targets a use case with Influx where I want to run the same benchmark multiple times under different constraints/scenarios.

For example:
```
for size in [10, 100, 1000] {
    Benchmark("TestFoo", tags: [ "size": size ]) {
        foo(size)
    }
}
```

This would allow me to get better dimensionality on a benchmark that, when exported to Influx, is more easily queried etc.
This would require some amendments to the Influx format exporter to include these custom tags for the particular benchmark.

We (myself and/or @ORyanHampton) are happy to take this PR on - just don't want to spend time on it if it's not a direction that the community finds appropriate.

### Additional contract requirements

- Custom tags are supplied through `Benchmark.Configuration`, which accepts a `tags: [String: String]` parameter (defaulting to no tags).
- A benchmark exposes a `name` property. When no tags are configured, `name` is the benchmark's base name. When tags are configured, `name` is the base name followed by a space and a parenthesized, alphabetically sorted, comma-separated list of `key: value` pairs, for example `TestFoo (bin: 42, foo: bar, pi: 3.14)`.
