wit-parser provides poor error messages for a missing closing bracket
## Reproduction
`src/main.rs`
```rust
fn main() {
    wit_bindgen::generate!({
        world: "platform",
        path: "./wit"
    })
}
```
`Cargo.toml`
```
[package]
name = "wit-issue"
version = "0.1.0"
edition = "2021"

[dependencies]
wit-bindgen = "0.25.0"
```
`wit/world.wit`
```wit
package qux:qaz@2.0.0;

world platform {
  import observe;
}
```
`wit/observe.wit`
```wit
interface observe {
  record bar {
    a : string,
  }
```

Running: `cargo build --release`
```
error: failed to resolve directory while parsing WIT for path [/Users/caleb/scratch/wit-issue/./wit]

       Caused by:
         failed to parse package: /Users/caleb/scratch/wit-issue/./wit

       Caused by:
         expected `type`, `resource` or `func`, found eof
            --> /Users/caleb/scratch/wit-issue/./wit/world.wit:4:14
             |
           4 |   import observe;
             |              ^
 --> src/main.rs:2:5
  |
2 | /     wit_bindgen::generate!({
3 | |         world: "platform",
4 | |         path: "./wit"
5 | |     })
  | |______^
  |
  = note: this error originates in the macro `wit_bindgen::generate` (in Nightly builds, run with -Z macro-backtrace for more info)

error: could not compile `wit-issue` (bin "wit-issue") due to 1 previous error
```
## Expected
Some sort of error that tells me I'm missing a closing bracket.

### Additional contract requirements

- For the missing-delimiter-at-EOF scenario (an `interface` whose closing `}` is missing at the end of the file), the parser reports the error message exactly ``expected `type`, `resource` or `func`, found eof``.
- The error's source location points at the end of the file that is missing the delimiter (`observe.wit`, line 6, column 1), not at the file that imports it (`world.wit`).
- In the multi-file missing-delimiter scenario, locate the parse error at EOF in `observe.wit`, rather than at the import site in `world.wit`.
