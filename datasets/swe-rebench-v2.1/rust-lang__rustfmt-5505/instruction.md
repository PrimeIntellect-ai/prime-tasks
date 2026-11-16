Incorrect comment aligning with strange unicode characters
With this code:
```rust
fn main() {}

pub struct WhitespaceCharacters {
    pub space: char,
    pub nbsp: char,
    pub tab: char,
    pub newline: char,
}

impl Default for WhitespaceCharacters {
    fn default() -> Self {
        Self {
            space: '·',    // U+00B7
            nbsp: '⍽',    // U+237D
            tab: '→',     // U+2192
            newline: '⏎', // U+23CE
        }
    }
}
```
rustfmt incorrectly aligns the comments, so that the one next to space is one character past the others.
Note that in utf8 the character next to space is 2 bytes, while the others they are 3 bytes.
Changing the chars to more basic ASCII chars resolves the issue:
```rust
impl Default for WhitespaceCharacters {
    fn default() -> Self {
        Self {
            space: 'h',   // U+00B7
            nbsp: 'i',    // U+237D
            tab: 'j',     // U+2192
            newline: 'k', // U+23CE
        }
    }
}
```
```
cargo fmt --version
rustfmt 1.5.1-stable (4b91a6e 2022-08-08)
```
