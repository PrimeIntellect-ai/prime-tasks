Applying an underline only to the table heading, not the entire cell
The following code:

```rust
let mut table = Table::new();
table.load_preset(comfy_table::presets::NOTHING);
table.set_header(vec![
    "A heading".bold(),
    "Column 1".bold(),
    "A slightly longer heading".bold(),
]);
for i in 0..5 {
    let row: Vec<_> = (0..3).map(|j| format!("Row {} col {}", i, j)).collect();
    table.add_row(row);
}
```

produces a table with misaligned headings.

![screenshot-211107-202200](https://user-images.githubusercontent.com/6341745/140658992-a11a3d06-432b-4260-a868-1c27b1053b9d.png)

If I coerce each row into a `Vec<StyledContent<String>>` by calling `.reset()` on the `String`s:

```rust
let mut table = Table::new();
table.load_preset(comfy_table::presets::NOTHING);
table.set_header(vec![
    "A heading".bold(),
    "Column 1".bold(),
    "A slightly longer heading".bold(),
]);
for i in 0..5 {
    let row: Vec<_> = (0..3)
        .map(|j| format!("Row {} col {}", i, j).reset()) // Change.
        .collect();
    table.add_row(row);
}
```

the problem goes away.

![screenshot-211107-202527](https://user-images.githubusercontent.com/6341745/140658993-2722d11d-346f-4f41-995d-983632922684.png)

### Additional contract requirements

Text-only styling is an opt-in rendering mode for tables containing styled cell text and ordinary string cells. Enable it on a table with `Table::style_text_only()`. When styling is enabled, the visible cell text remains styled, but whitespace used only for alignment or padding is not styled. Enabling this mode must preserve the table's column alignment when rendering styled headings alongside ordinary string body rows.
