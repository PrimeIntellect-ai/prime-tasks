`empty_item_single_line` should apply to trait definitions as well
1.4.37-nightly

Using this rustfmt.toml

```toml
brace_style = "AlwaysNextLine"
empty_item_single_line = true
```
rustfmt will format the following code like this:

```rust
fn function() {}

struct Struct {}

enum Enum {}

trait Trait
{
}

impl<T> Trait for T {}
```

This is inconsistent, and empty traits end up sticking out like a sore thumb. Intended behaviour is probably this:

```rust
fn function() {}
struct Struct {}
enum Enum {}
trait Trait {}
impl<T> Trait for T {}
```

This is important, as empty traits are often quite useful. For instance, you might want something like this:

```rust
trait Trait: Send + Clone {}
impl<T: Send + Clone> Trait for T {}
```

which will look quite ugly at the moment.
