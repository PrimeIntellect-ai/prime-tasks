the trait `BorshSerialize` is not implemented for `PhantomData<MyMarker>`
serialize it to 0 bytes

### Additional contract requirements

- `PhantomData<T>` implements `BorshSerialize` and `BorshDeserialize` for any type parameter `T`, including unsized types (`T: ?Sized`).
- Serializing a `PhantomData<T>` writes zero bytes.
- Deserializing a `PhantomData<T>` always succeeds, returns `PhantomData::default()`, and consumes no bytes from the input.
