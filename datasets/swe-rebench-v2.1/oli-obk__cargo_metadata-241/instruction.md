Non numerical values for debuginfo cannot be parsed from cargo messages
Valid values for debuginfo level now also include strings "line-tables-only" and "line-directives-only", see [here](https://doc.rust-lang.org/cargo/reference/profiles.html#debug).

`cargo` will emit those as part of json output. `profile` for an can look artifact look like this

```json
"profile":{"opt_level":"3","debuginfo":"line-tables-only","debug_assertions":false,"overflow_checks":false,"test":false},
```
I'm trying to parse it into `cargo_metadata::messages::Message` datatype and it fails to parse it, probably because
[`ArtifactProfile`](https://docs.rs/cargo_metadata/latest/cargo_metadata/struct.ArtifactProfile.html) defines `debuginfo` as `Option<u32>`

https://github.com/pacak/cargo-show-asm/issues/187 - related ticket
