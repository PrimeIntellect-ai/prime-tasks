get_mut2/query_one2 (or similar functionality?)
There are a few cases where it would be very useful to be able to reference multiple distinct entities w/ potentially the same components, at the same time. The only way this is currently possible is through the `get_unchecked` methods, or with a query which is later filtered out or collected into an auxiliary structure. Unless I've missed something?

### Additional contract requirements

Add a public method `get_mut_n` on `hecs::View` with the signature:

```rust
pub fn get_mut_n<const N: usize>(&mut self, entities: [Entity; N]) -> [Option<QueryItem<'q, Q>>; N]
```

It returns an array of length `N` where each element is `Some` with the query result for the corresponding entity if that entity exists and possesses the requested component(s), and `None` otherwise. It panics if any two entries in `entities` are equal.
