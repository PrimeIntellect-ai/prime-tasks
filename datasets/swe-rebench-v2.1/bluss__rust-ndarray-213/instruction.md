`Default` trait for `ArrayBase`?
What is the opinion on implementing `std::default::Default` for `ArrayBase`? When skipping deserialization of a field with `serde`, it wants to insert the `Default::default()` value in there, so this would be one case where this would be very useful.

We already have a default function for `ArrayBase`, which however expects some kind of shape/dimension:

```rust
    pub fn default<Sh>(shape: Sh) -> ArrayBase<S, D>
        where A: Default,
              Sh: Into<Shape<D>>,
    {
        let shape = shape.into();
        let v = (0..shape.dim.size()).map(|_| A::default()).collect();
        unsafe { Self::from_shape_vec_unchecked(shape, v) }
    }
```

A default in the spirit of `std::default::Default` would look like:

```rust
    pub fn default() -> ArrayBase<S, D>
        where A: Default,
              D: Default + Default,
              Sh: Into<Shape<D>>,
    {
        [HIDDEN]
    }
```

And `Default` impls for the various dimension-like types would be akin to:

```rust
impl Default for Ix {
    fn default() -> Self {
        0 as Ix
    }
}

impl Default for (Ix,Ix) {
    fn default() -> Self {
        (0,0) as (Ix,Ix)
    }
}
```

Is this desirable?

**EDIT:** I just realize that this might not be as straightforward as I thought, since e.g. `Ix` acts as just a type alias, preventing an easy implementation of `Default` for it. :-/

### Additional contract requirements

- Implement `std::default::Default` for owned `ArrayBase` values where `A: Default`, `S: DataOwned<Elem = A>`, and `D: Dimension + Default`.
- The resulting array has the shape provided by the default value of `D`, and each element is initialized with `A::default()`.
