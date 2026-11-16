rustfmt stops working if the comment just after the => of a "match" contains "=>"
Hello,

I've noticed that rustfmt stops working if the comment just after the => of a "match" contains "=>".

info :
rustfmt 1.7.0-stable (82e1608 2023-12-21)
rustc 1.75.0 (82e1608df 2023-12-21)


here's an example code :
```rust
fn main() {
    let a = 50u32;
    match a {
        10 =>
        // comment => 10
                {
            println!("A")
        }
        20 => {
                            println!("B")
        }
        _ => {
            println!("C")
        }
    }
}
```

the problem is in the comment :
`// comment => 10`

the comment contains the symbol "=>", if you try to use rustfmt it won't work.
but if you delete the "=>" from the comment, or simply add a space like this "= >", rustmt works again.

you can test the bug here :  ( click on the top-right "Tools -> Rustfmt" button to start formatting, but it won't work as long as the comment contains "=>" )
[Playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=41d70dfff0c31abd78d5cbe156481439)

Thank you for the wonderful work that you do :+1:
