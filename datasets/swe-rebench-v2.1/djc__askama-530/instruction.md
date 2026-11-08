Build error thanks to bitvec vs funty
I have a project using `askama@0.10.5` and `mysql@21.0.0` which leaves me with the following

```
├── askama v0.10.5
│   ├── askama_derive v0.10.5 (proc-macro)
│   │   ├── askama_shared v0.11.1
│   │   │   ├── askama_escape v0.10.1
│   │   │   ├── humansize v1.1.1
│   │   │   ├── nom v6.1.1
│   │   │   │   ├── bitvec v0.19.4
│   │   │   │   │   ├── funty v1.2.0
│   │   │   │   │   ├── radium v0.5.3
│   │   │   │   │   ├── tap v1.0.1
│   │   │   │   │   └── wyz v0.2.0
│   │   │   │   ├── lexical-core v0.7.5
│   │   │   │   │   ├── arrayvec v0.5.2
│   │   │   │   │   ├── bitflags v1.2.1
│   │   │   │   │   ├── cfg-if v1.0.0
│   │   │   │   │   ├── ryu v1.0.5
│   │   │   │   │   └── static_assertions v1.1.0
│   │   │   │   └── memchr v2.3.4
│   │   │   │   [build-dependencies]
│   │   │   │   └── version_check v0.9.2
│   │   │   ├── num-traits v0.2.14
│   │   │   │   [build-dependencies]
│   │   │   │   └── autocfg v1.0.1
│   │   │   ├── percent-encoding v2.1.0
│   │   │   ├── proc-macro2 v1.0.24 (*)
│   │   │   ├── quote v1.0.9 (*)
│   │   │   ├── serde v1.0.124 (*)
│   │   │   ├── syn v1.0.61 (*)
│   │   │   └── toml v0.5.8
│   │   │       └── serde v1.0.124 (*)
│   │   ├── proc-macro2 v1.0.24 (*)
│   │   └── syn v1.0.61 (*)
│   ├── askama_escape v0.10.1
│   └── askama_shared v0.11.1 (*)
├── askama_derive v0.10.5 (proc-macro) (*)
├── askama_shared v0.11.1 (*)
```

The key thing (if I understood this) is that here we have `bitvec@0.19.4`.

Elsewhere in my dependency tree I have:

```
│   ├── mysql_common v0.27.4
│   │   ├── base64 v0.13.0
│   │   ├── bigdecimal v0.2.0
│   │   │   ├── num-bigint v0.3.2
│   │   │   │   ├── num-integer v0.1.44 (*)
│   │   │   │   └── num-traits v0.2.14 (*)
│   │   │   │   [build-dependencies]
│   │   │   │   └── autocfg v1.0.1
│   │   │   ├── num-integer v0.1.44 (*)
│   │   │   ├── num-traits v0.2.14 (*)
│   │   │   └── serde v1.0.124 (*)
│   │   ├── bitflags v1.2.1
│   │   ├── bitvec v0.22.3
│   │   │   ├── funty v1.2.0
│   │   │   ├── radium v0.6.2
│   │   │   ├── tap v1.0.1
│   │   │   └── wyz v0.4.0
│   │   │       └── tap v1.0.1
│   │   ├── byteorder v1.4.2
│   │   ├── bytes v1.0.1
│   │   ├── chrono v0.4.19 (*)
```

`bitvec@0.22.3` and `funty@1.2.0` work well enough together as evidenced by a min project I put together with just the two of them, but the build specifically mentions `0.19.4`:

```
error[E0034]: multiple applicable items in scope
   --> /home/leeh/.asdf/installs/rust/1.53.0/registry/src/github.com-1ecc6299db9ec823/bitvec-0.19.4/src/order.rs:315:15
    |
315 |         if ct == R::BITS {
    |                     ^^^^ multiple `BITS` found
    |
note: candidate #1 is defined in the trait `BitMemory`
   --> /home/leeh/.asdf/installs/rust/1.53.0/registry/src/github.com-1ecc6299db9ec823/bitvec-0.19.4/src/mem.rs:29:2
    |
29  |     const BITS: u8 = mem::size_of::<Self>() as u8 * 8;
    |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
note: candidate #2 is defined in the trait `IsNumber`
   --> /home/leeh/.asdf/installs/rust/1.53.0/registry/src/github.com-1ecc6299db9ec823/funty-1.2.0/src/lib.rs:144:2
    |
144 |     const BITS: u32;
    |     ^^^^^^^^^^^^^^^^
help: disambiguate the associated constant for candidate #1
    |
315 |         if ct == BitMemory::BITS {
    |                  ^^^^^^^^^^^^^^^
help: disambiguate the associated constant for candidate #2
    |
315 |         if ct == IsNumber::BITS {
    |                  ^^^^^^^^^^^^^^

error: aborting due to 43 previous errors

Some errors have detailed explanations: E0034, E0308.
For more information about an error, try `rustc --explain E0034`.
error: could not compile `bitvec`
```

I reported it here because we have here in `askama` as `nom@6.1.1` as a dependency is inherited here.

[HIDDEN] https://github.com/Geal/nom/issues/1311#issuecomment-880902973

I tried in a small patch, something like:

``` diff
diff --git a/askama_shared/Cargo.toml b/askama_shared/Cargo.toml
index e341b2e..95775e4 100644
--- a/askama_shared/Cargo.toml
+++ b/askama_shared/Cargo.toml
@@ -19,8 +19,8 @@ yaml = ["serde", "serde_yaml"]
 [dependencies]
 askama_escape = { version = "0.10", path = "../askama_escape" }
 humansize = { version = "1.1.0", optional = true }
[HIDDEN]
 num-traits = { version = "0.2.6", optional = true }
 proc-macro2 = "1"
 quote = "1"
```

This seems to work locally, and `cargo clean && cargo test` seems to be :heavy_check_mark: - I'd be happy to send a PR for that, and bumping version numbers and the release notes/etc. Please just let me know. I'm switching my project to my own git fork of `askama` and check if it's working.

### Additional contract requirements

- The Askama package version must be `0.11.0-beta.1`.
- With the dependency combination described, building the project must not fail due to the reported `bitvec`/`funty` compiler errors reached through Askama's `nom` dependency.
