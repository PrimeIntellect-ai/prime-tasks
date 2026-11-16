"Remove `dbg!` in selection" does not remove nested ones
Removing all `dbg!()` macros in the selection was implemented in #13629 , but it does not remove nested `dbg!()` .

Minimal repro:
```rust
fn main() {
  let x = dbg!(dbg!(0) + 1) + 2; // Select this line and run the code action
}
```
Expected result:
```rust
fn main() {
  let x = (0 + 1) + 2;
}
```
Actual result:
```rust
fn main() {
  let x = (dbg!(0) + 1) + 2;
}
```
Running the action once more yields the desired result.

**rust-analyzer version**  `[coc.nvim] rust-analyzer 0.3.1348-standalone`
**rustc version**: (eg. output of `rustc -V`)
```
rustc 1.65.0 (897e37553 2022-11-02)
```
**relevant settings**: Nothing shuold be relevant.
