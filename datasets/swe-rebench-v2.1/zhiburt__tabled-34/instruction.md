Hidden fields shouldn't need to implement Display
I have a field of a struct which I do not plan to show in the table output. However, despite adding:
```rust
    #[header(hidden = true)]
    foo: SomeType
```
I still have an error compiling the struct, saying `SomeType` doesn't implement display. Obviously, I don't want to go through the trouble of implementing `Display` for a type I don't plan to list in the table. If possible, there should be a way to completely disable parsing for this field so that not having `Display` implemented for a field which is hidden doesn't error out.
