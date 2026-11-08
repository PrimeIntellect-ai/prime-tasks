"the trait `From<std::path::Display<'_>>` is not implemented for `Cow<'_, _>`"
The following example results in an error spelled out in the title:

```rust
#[derive(tabled::Tabled)]
struct MyStruct<'a> {
    #[tabled(display_with("std::path::Path::display"))]
    path: &'a std::path::Path,
}
```

`tabled` only says that it requires types to be `Display`, but here is it also trying to construct a `Cow` of something from that `Display` impl.
