Default binding modes are hard
The hover data reported for variable `x` here indicates that rust and r-a disagree about what to do when pattern matching a reference with "match ergonomics". We are matching `&true` against the pattern `x @ true`, and rust interprets it as `&(x @ true)` while r-a interprets it as `x @ &true`, leading to an incorrect typing annotation.
```rust
fn main() {
    if let x @ true = &true {
        //            v hover says `x: bool`
        let _: bool = x;
        // rust says: expected `bool`, found `&bool`
    }
}
```
