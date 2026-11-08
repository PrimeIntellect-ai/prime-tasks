request: option to also enumerate second-order features
A little known thing is you can do:

```
 cargo test --features "foo/bar"
```

Which activates the "bar" feature of the "foo" crate. ( it makes sense when you see how features are defined in Cargo.toml ).

Subsequently, this means there is a way to expand test coverage to test situations where somebody turns on that feature in a different crate, and you get it through cargo composition.

So it would be nice if there was a way to test these, understandably, the set size it may generate could be prohibitively large in some cases, so its not a sensible default.

### Additional contract requirements

- The CLI adds a `--include-deps-features` flag. It is used together with `--each-feature` to enumerate the features of dependencies as additional scenarios.
- When `cargo check --each-feature --include-deps-features` is run for the `cargo-hack` package, the progress output on stderr lists a scenario for each feature of each dependency, in the form `running \`cargo check --no-default-features --features <dependency>/<feature>\` on cargo-hack`.
- When `--include-deps-features` is used with Cargo older than 1.41, stderr contains `--all-features requires Cargo 1.41 or leter`.
