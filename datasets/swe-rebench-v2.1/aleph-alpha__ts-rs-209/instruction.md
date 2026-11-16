Allow emitting arrays as TS tuples
```rust
pub(crate) struct Scene {
    color: [f32; 4],
}
```
currently becomes an array of uncertain length,
```typescript
export interface Scene {
  color: Array<number>;
}
```

It would be useful to be able to mark this e.g.

```rust
pub(crate) struct Scene {
    #[ts(tuple)]
    color: [f32; 4],
}
```
to emit it as
```typescript
export interface Scene {
  color: [number, number, number, number];
}
```

I tried my hand at implementing this myself, but got lost in macros...

### Additional contract requirements

Fixed-size Rust arrays `[T; N]` are rendered as TypeScript tuples: the element type repeated `N` times inside brackets, e.g. `[number, number, number, number]` for `[f32; 4]`. This applies to array fields of derived structs, newtypes and generic structs, and to the `inline()` and `decl()` output of such types.

Arrays with more than 128 elements are rendered as `Array<T>` instead of a tuple. A zero-length array `[T; 0]` is rendered as `[]`.

The `TS` trait methods on `[T; N]` follow the same rules:
- `inline()` returns the tuple literal for `N <= 128`, `Array<T>` for `N > 128`, and `[]` for `N = 0`.
- `name_with_type_args(args)` returns the tuple literal built from `args[0]` for `N <= 128`, `Array<args[0]>` for `N > 128`, and `[]` for `N = 0`.
- `name()` returns `[]` for `N <= 128` and `Array` for `N > 128`.
