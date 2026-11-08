Parsed `Key` misbehaves, can panic
When using `string.parse::<toml_edit::Key>()`, the value of the key *changes* when inserted into a document.

For example, the following snippet fails, because a key of `bbb` should have been inserted into the doc, but instead `aaa` is inserted into the doc. (Presumably this has to do with the fact that the key is represented as a `RawStringInner::Spanned`.)

```rust
use toml_edit::{Document, Key, Item, Value, Formatted};

fn main() {
    let mut doc = r#"aaaaaa = 1"#.parse::<Document>().unwrap();
    let key = "bbb".parse::<Key>().unwrap();
    let mut table = doc.as_table_mut();
    table.insert_formatted(&key, Item::Value(Value::Integer(Formatted::new(2))));

    assert_eq!(doc.to_string(), "aaaaaa = 1\nbbb = 2\n");
}
```

https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=24543f24fd94c8622e88929df3f1c1f0

If the original document is shorter than the length of the key, this will panic.

```rust
use toml_edit::{Document, Key, Item, Value, Formatted};

fn main() {
    let mut doc = r#"a=1"#.parse::<Document>().unwrap();
    let key = "bbbbbb".parse::<Key>().unwrap();
    let mut table = doc.as_table_mut();
    table.insert_formatted(&key, Item::Value(Value::Integer(Formatted::new(2))));

    assert_eq!(doc.to_string(), "a=1\nbbbbbb = 2\n");
}
```

    thread 'main' panicked at 'span 0..6 should be in input:
    ```
    a=1
    ```'

https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=f2b0eaaa343155ef54002a7242013184

This seems to have started in version 0.18
