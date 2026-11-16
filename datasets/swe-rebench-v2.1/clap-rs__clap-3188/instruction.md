use `default_value_t` with `ArgEnum` without manually implementing `Display`
### Please complete the following tasks

- [X] I have searched the [discussions](https://github.com/clap-rs/clap/discussions)
- [X] I have searched the existing issues

### Clap Version

master

### Describe your use case

deriving argenums with default values is currently a little clumsy, since you have to manually implement `Display`, and you need to manually ensure that the `Display` implementation is aligned with the derived `ArgEnum` implementation


for example

```rust
#[derive(Debug, Parser)]
pub struct List {

    #[clap(long, arg_enum, default_value_t]
    variant: Variant
}

#[derive(Debug, Clone, Copy, ArgEnum)]
enum Variant {
    ObjectA,
    ObjectB
}

impl std::fmt::Display for Variant {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            Self::ObjectA => "object-a", // or is it "object_a"?
            Self::ObjectB => "object-b",
        };
        write!(f, "{}", s)
    }
}
```

what i'd *like* is to omit the manual `Display` implementation

### Describe the solution you'd like

`#[derive(ArgEnum)]` should generate a `Display` implementation which is consistent with the input values that it accepts

### Alternatives, if applicable

- `clap` provide a `Display` derive that is implemented in terms of `ArgEnum`
- Specialize `default_value_t` support for `ArgEnum`

### Additional Context

one possible edge case is that the derived `Display` implementation could conflict with another `Display` implementation (in which case `default_value_t` shouldn't be used anyway!)

therefore the generated `Display` implementation could have a flag to opt in or out (i would vote for making it opt out)
