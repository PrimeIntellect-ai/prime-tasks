BTreeMap serialization missing in 0.8.0 update
The ability to serialize BTreeMaps is suddenly missing in the new update, is this intentional?

https://docs.rs/borsh/0.7.1/src/borsh/ser/mod.rs.html#235-251 <- present
https://docs.rs/borsh/0.8.0/src/borsh/ser/mod.rs.html#235-251 <- missing

```
#[derive(BorshSerialize, BorshDeserialize)]
    |          ^^^^^^^^^^^^^^ the trait `BorshSerialize` is not implemented for `BTreeMap<std::string::String, Vec<Vec<u8>>>`
    |
    = help: see issue #48214
    = help: add `#![feature(trivial_bounds)]` to the crate attributes to enable
    = note: this error originates in a derive macro (in Nightly builds, run with -Z macro-backtrace for more info)

error: aborting due to previous error

For more information about this error, try `rustc --explain E0277`.
error: could not compile `test-program`
```
