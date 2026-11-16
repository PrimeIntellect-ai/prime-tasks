f64::INFINITY causes panic
# Problem summary

I need to be able to serialize and deserialize `f64::INFINITY` in my code.  I believe that this should be possible, but the following code causes a panic when run:

```rust
use ron::de;
use ron::ser;
use serde::*;
use std::cmp::{Eq, PartialEq};
use std::f64;

#[derive(Copy, Clone, Debug, Default, Serialize, Deserialize)]
pub struct Test1 {
    field: f64,
}

impl PartialEq for Test1 {
    fn eq(&self, other: &Test1) -> bool {
        self.field == other.field
    }
}

impl Eq for Test1 {}

fn main() {
    let original = Test1 {
        field: f64::INFINITY,
    };

    let pretty: ser::PrettyConfig = Default::default();
    let serialized = ser::to_string_pretty(&original, pretty.clone()).unwrap();
    let duplicate: Test1 = de::from_str(&serialized).unwrap();
    assert_eq!(original, duplicate);
}
```
There is no panic for finite `f64` values.

The panic:
```
$ cargo run
   Compiling serde_float_issue v0.1.0 (/home/cfkaran2/Desktop/bug_reports/serde_float_issue)
    Finished dev [unoptimized + debuginfo] target(s) in 0.49s
     Running `target/debug/serde_float_issue`
thread 'main' panicked at 'called `Result::unwrap()` on an `Err` value: Parser(ExpectedFloat, Position { col: 12, line: 2 })', src/libcore/result.rs:997:5
note: Run with `RUST_BACKTRACE=1` environment variable to display a backtrace.
```

# Meta information:

```$ uname -a ; echo ; lsb_release --all ; echo ; rustc -Vv ; echo ; cargo -Vv
Linux EMANE 4.15.0-47-generic #50-Ubuntu SMP Wed Mar 13 10:44:52 UTC 2019 x86_64 x86_64 x86_64 GNU/Linux

No LSB modules are available.
Distributor ID:	Ubuntu
Description:	Ubuntu 18.04.2 LTS
Release:	18.04
Codename:	bionic

rustc 1.34.0 (91856ed52 2019-04-10)
binary: rustc
commit-hash: 91856ed52c58aa5ba66a015354d1cc69e9779bdf
commit-date: 2019-04-10
host: x86_64-unknown-linux-gnu
release: 1.34.0
LLVM version: 8.0

cargo 1.34.0 (6789d8a0a 2019-04-01)
release: 1.34.0
commit-hash: 6789d8a0a54a96d95365c4e1fb01d47a5eed9937
commit-date: 2019-04-01
```
