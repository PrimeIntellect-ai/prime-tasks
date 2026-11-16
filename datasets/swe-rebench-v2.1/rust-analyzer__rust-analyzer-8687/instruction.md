Closure types aren't always inferred correctly.
Using the VS Code-provided v0.2.565 of RA, the `sub` closure in the following code isn't being inferred.
[Screenshot of the incorrect inlay hint](https://i.imgur.com/E50fDmG.png)
```rust
fn foo(c: i32) -> Box<dyn Fn(i32, i32) -> i32> {
    let add = |a, b| a + b;
    let sub = |a, b| a - b;
    Box::new(if c > 42 { add } else { sub })
}

fn main() {
    println!("{}", foo(100)(10, 20));
}
```
