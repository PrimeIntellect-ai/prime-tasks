Parser doesn't handle whitespace ...
between `(` and `[` of a `newtype_struct` wrapping a `seq`:

```rust

#[derive(Debug, Deserialize)]
struct Newtype(Vec<String>);

fn main() {
    let serialized = stringify!(
        Newtype([
            "a",
            "b",
            "c",
        ])
    );
    println!("{}", serialized);
    let deserialized: Result<Newtype, _> = ron::de::from_str(serialized);
    println!("{:#?}", deserialized);


    let serialized = r#"
        Newtype([
            "a",
            "b",
            "c",
        ])
    "#;
    println!("{}", serialized);
    let deserialized: Result<Newtype, _> = ron::de::from_str(serialized);
    println!("{:#?}", deserialized);
}
```

```
Newtype ( [ "a" , "b" , "c" , ] )
Err(
    Parser(
        ExpectedArray,
        Position {
            col: 10,
            line: 1
        }
    )
)

        Newtype([
            "a",
            "b",
            "c",
        ])

Ok(
    Newtype(
        [
            "a",
            "b",
            "c"
        ]
    )
)
```

(This is what I actually came here to report when I got sidetracked by the linguist+ronn history dive 😆)
