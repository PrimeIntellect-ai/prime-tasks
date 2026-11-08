Disabled variant still included in Count
The [additional attributes docs](https://docs.rs/strum/latest/strum/additional_attributes/index.html#attributes-on-variants) define the `disabled` attribute as:

> `disabled`: removes variant from generated code.

However, when deriving the `EnumCount` trait, the disabled variant is still counted in the final count.


Here is some example code:

```rust
use strum::EnumCount;

#[derive(strum::EnumCount)]
enum Fields {
    Field0,
    Field1,
    Field2,
    #[strum(disabled)]
    Unknown,
}

fn main() {
    println!("Count: {}", Fields::COUNT);
}
````

Expected output: `Count: 3`
Actual output: `Count: 4`

This issue seems similar to #244
