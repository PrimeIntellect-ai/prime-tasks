strum::Display doesn't work with non-unit non-string variants
strum::Display and #[strum(default)] doesn't work with non-unit non-string variants.   It should probably try to convert the enclosed tuple into a string?

```
#[derive(strum::Display)]
enum Color {
    Red,
    Blue,
    Green,
}
#[derive(strum::Display)]   <---- this fails: Mismatched types.
enum TestEnum {
    #[strum(default)]
    Color(Color),
}
```
