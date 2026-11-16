Overlapping Panels throw uncaught errors
### Issue and Steps to Reproduce

When using the [Panel](https://github.com/zhiburt/tabled/blob/master/tabled/src/settings/panel/mod.rs) setting, if you insert horizontal and vertical panels that overlap each other it causes the application to crash.

You can easily test this scenario by visiting the Panel example, and changing either of the vertically injected panels to 1-4; conflicting with the previously applied table-length horizontal panels.
https://github.com/zhiburt/tabled/blob/837bed213e824ced96cd7e9dc18a0c8c439fc314/tabled/examples/panel.rs#L43-L57

### Expected Behavior

It would be in keeping with other fault-tolerant table settings that if these functions cannot resolve, they simply return without making any modifications. Although perhaps, for Panel, it could be an option to have the most recently applied panel nest within those before it? Maybe look something like this (rather than crash):

<img width="549" alt="Screenshot 2023-03-31 at 12 42 04 PM" src="https://user-images.githubusercontent.com/46393653/229180332-38a943ac-fa83-426d-928d-76fb52b45262.png">

```rust
table
    .with(Panel::header("Tabled Releases"))
    .with(Panel::footer(format!("N - {}", DATA.len())))
    .with(Panel::vertical(0, "Some text goes here"))
    .with(Panel::vertical(4, "Some text goes here")) // <-- changed
```

### Additional Details
* I also tested this scenario with [Span](https://github.com/zhiburt/tabled/blob/master/tabled/src/settings/span/mod.rs) and it crashes as well. It would seem that conflicting spans are the real issue I'm documenting here 😆

### Additional contract requirements

Applying a span that conflicts with an existing span must not panic. If a Panel placement conflicts with an existing span and cannot be applied, the table must remain unchanged.
