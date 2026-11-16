Fix `Panel` style rendering on tables with more than 2 columns
Running this code will result in the following.

```rust
use tabled::{Style, Table};

fn main() {
    let table = Table::new(&[(0, 1)])
        .with(tabled::Panel("Numbers", 0))
        .with(Style::modern());

    println!("{}", table);
}
```

```rust
┌───────────┬
│Numbers    │
├───────────┼
│ i32 │ i32 │
├─────┼─────┤
│  0  │  1  │
└─────┴─────┘
```

As you may see the styles on the right side is not exactly correct.
It would be good to be fixed.
