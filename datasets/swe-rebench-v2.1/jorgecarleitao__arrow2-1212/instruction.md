`ndjson::read::infer` does not maintain proper column ordering
version: `{ git = "https://github.com/jorgecarleitao/arrow2", rev = "8604cb760b8ac475d7968b714d47e4ff714c61a1", default-features = false }`
rust version:
```sh
> rustup show

active toolchain
----------------

nightly-x86_64-unknown-linux-gnu (directory override for '/<redacted>')
rustc 1.64.0-nightly (0f4bcadb4 2022-07-30)
```


## Expected
The ordering of the original Json should be maintained when inferring the datatype.

## Actual
The ordering appears to be deterministic, but not in the correct order. Multiple runs of the code seems to always produce `[bools, f64, u64, utf8]` instead of the expected `[u64, f64, utf8, bools]`



```rust
use arrow2 as arrow;

let mut data: &[u8] = r#"{"u64": 1, "f64": 0.1, "utf8": "foo1", "bools": true}
    {"u64": 2, "f64": 0.2, "utf8": "foo2", "bools": false}
    {"u64": 3, "f64": 0.3, "utf8": "foo3"}
    {"u64": 4, "f64": 0.4, "utf8": "foo4", "bools": false}
    "#
.as_bytes();
let u64_fld = arrow::datatypes::Field::new("u64", arrow::datatypes::DataType::UInt64, true);
let f64_fld = arrow::datatypes::Field::new("f64", arrow::datatypes::DataType::Float64, true);
let utf8_fld = arrow::datatypes::Field::new("utf8", arrow::datatypes::DataType::Utf8, true);
let bools_fld = arrow::datatypes::Field::new("bools", arrow::datatypes::DataType::Boolean, true);

let expected = arrow::datatypes::DataType::Struct(vec![u64_fld, f64_fld, utf8_fld, bools_fld]);
let actual = arrow::io::ndjson::read::infer(&mut data, None).unwrap();

println!("expected={:#?}", expected);
println!("actual={:#?}", actual);
assert_eq!(expected, actual);
```
