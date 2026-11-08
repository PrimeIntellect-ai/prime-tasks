Adding context breaks type inference
Adding context seems to break type inference. For example:

```rust
use anyhow::{Context, Result};

fn main() -> Result<()> {
    let x = "k";
    let y: u32 = x.parse().context("context")?;
    println!("{}", y);
    Ok(())
}
```

gives

```
error[E0284]: type annotations required: cannot resolve `<_ as std::str::FromStr>::Err == _`
 --> src\main.rs:5:20
  |
5 |     let y: u32 = x.parse().context("context")?;
  |
```

obviously using turbofish syntax works, like:

```rust
let y = x.parse::<u32>().context("context")?;
```

but it is surprising behaviour. Might be a compiler limitation but I still wanted to mention it.
