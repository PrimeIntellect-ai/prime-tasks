Newtype as the key of a `HashMap`/`BTreeMap` is not supported
A newtype - a named single-tuple type - cannot be used as the key of a `HashMap` or a `BTreeMap`.

[playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=ecabf606f065a4c82d7c4de0cb1c720d)
```rust
use std::collections::HashMap;
use serde::Deserialize;

#[derive(PartialEq, Eq, Hash, Debug, Deserialize)]
struct NewType(String);

fn main() -> anyhow::Result<()> {
    let map = toml::from_str::<HashMap<NewType, u32>>(r#"
    x = 1
    y = 2
    "#)?;
    println!("{map:?}");
    Ok(())
}
```

```
Error: TOML parse error at line 2, column 5
  |
2 |     x = 1
  |     ^
invalid type: string "x", expected tuple struct NewType
```

This is contrary to `serde_json`.

[playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=7c51f0b4d7b60349402c1cbad6a44bf1)
```rust
use std::collections::HashMap;
use serde::Deserialize;

#[derive(PartialEq, Eq, Hash, Debug, Deserialize)]
struct NewType(String);

fn main() -> anyhow::Result<()> {
    let map = serde_json::from_str::<HashMap<NewType, u32>>(r#"
    {"x": 1, "y": 2}
    "#)?;
    println!("{map:?}");
    Ok(())
}
```

```
{NewType("x"): 1, NewType("y"): 2}
```

I ran into this issue in my project, and I think that this should definitely be supported.
