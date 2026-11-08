[Question] Consider make idna optional?
Background:
I am developing a rust sdk with strong binary size requirement, after introduce url crate, the binary size increased by around 400kb.
I did a quick hack, delete all code reference to idna (4 to 5 places), and compare the final binary size, confirmed idna is the cause.

```bash
# before
-rwxr-xr-x  1 xxxxxx staff  1143856 Nov 16 12:12 ../target/release/deps/parse_url-124867e06fe8f448

# after delete idna code
-rwxr-xr-x  1 xxxxxx  staff  591008 Nov 16 12:16 ../target/release/deps/parse_url-8091d2463bfcb288
```

### Additional contract requirements

- The `idna` dependency must be optional, controlled by a Cargo feature named `idna` that is enabled by default.
- The crate must compile and its test suite must pass when built with `--no-default-features`, i.e. with the `idna` feature disabled.
- When the `idna` feature is disabled, IDNA processing is unavailable: parsing a URL whose host requires IDNA processing (a host containing non-ASCII characters) must fail with a parse error, while ASCII-only hosts must continue to parse successfully.
