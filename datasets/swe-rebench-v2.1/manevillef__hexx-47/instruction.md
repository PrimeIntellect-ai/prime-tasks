Return `ExactSizeIterator` from shapes where possible
https://github.com/ManevilleF/hexx/blob/9e7dc161e219e8d3147b4b1d3fc461504c14fe62/src/lib.rs#L156

This avoids needing to slowly count the iterator. This was particularly silly because iterators are consumed by doing so.

See this code that I wrote:

```rust
    /// Returns the average height of tiles around `tile_pos` within `radius`
    pub(crate) fn average_height(&self, tile_pos: TilePos, radius: u32) -> f32 {
        let hex_iter = hexagon(tile_pos.hex, radius);
        let n = hex_iter.count();
        let hex_iter = hexagon(tile_pos.hex, radius);
        let heights = hex_iter.map(|hex| *self.height_index.get(&TilePos { hex }).unwrap_or(&0.));
        heights.sum::<f32>() / n as f32
    }
```

### Additional contract requirements

- The following functions must return an `ExactSizeIterator` (not just an `Iterator`): `Hex::range`, `Hex::line_to`, `Hex::ring_edge`, `HexBounds::all_coords`, and the functions of the `shapes` module (`hexagon`, `triangle`, `parallelogram`, `pointy_rectangle`, `flat_rectangle`).
- For each of these, `len()` reports the total number of items the iterator will yield, and `size_hint()` returns that same exact value as both bounds.
- Calling `len()` must not consume items. After each item is taken, `len()` and `size_hint()` decrease by exactly one.
- The items yielded by these functions, and their order, are unchanged from the existing behaviour.
