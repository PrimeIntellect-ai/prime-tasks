Update breaks 11-bit parser- always Incomplete
## Prerequisites

I saw your blog post today about the new version, congrats! I have a small bit of nom from a while ago I'm trying to upgrade but it appears the behaviour is different.

In your 'upgrading to 4' design doc, you mentioned that 4 is stricter with 'Incomplete' however in this case the data is already here, I am not waiting on anything (in the real program the Vec isn't pasted in but already allocated, the result is the same). I've made the appropriate syntax changes.

- Rust version : `rustc -V` 1.27
- nom version : 1.2 works 4 doesn't
- nom compilation features used:
macros

## Test case
working (will print an idx for every 11 bits in the Vec):


```rust
#[macro_use]
extern crate nom;
use nom::IResult;
fn main() {
        named!(bit_vec<Vec<u16>>, bits!(many0!(take_bits!(u16, 11))));

        let m: Vec<u8> = vec![70, 97, 106, 121, 86, 66, 105, 98, 86, 106, 101, 72, 57, 101, 52, 118, 73, 72, 80, 115, 83, 71, 52, 78, 104, 67, 56, 122, 49, 98, 76, 53, 141];
        let mut mnem_words = Vec::new();
        if let IResult::Done(_, bit_sequence) = bit_vec(m.as_slice()) {
            for idx in &bit_sequence {
                 println!("{:?}", idx);
            }
        }
}
```


not working, says Incomplete, will not print any idx values:
```rust
#[macro_use]
extern crate nom;
use nom::IResult;
fn main() {
        named!(bit_vec<Vec<u16>>, bits!(many0!(take_bits!(u16, 11))));

        let m: Vec<u8> = vec![70, 97, 106, 121, 86, 66, 105, 98, 86, 106, 101, 72, 57, 101, 52, 118, 73, 72, 80, 115, 83, 71, 52, 78, 104, 67, 56, 122, 49, 98, 76, 53, 141];
        let mut mnem_words = Vec::new();
        if let Ok((_, bit_sequence)) = bit_vec(m.as_slice()) {
            for idx in &bit_sequence {
                 println!("{:?}", idx);
            }
        }
}
```

### Additional contract requirements

When parsing a complete input as repeated 11-bit values, return all complete values available even if fewer than 11 bits remain for another value. A short remainder of a complete input must not cause the parse to return `Incomplete`.
