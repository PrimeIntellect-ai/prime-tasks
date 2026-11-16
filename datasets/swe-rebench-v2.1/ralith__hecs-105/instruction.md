Add support for generic types to `#[derive(Bundle)]`
At current, the `Bundle` derive macro doesn't support generics and it seems to me like it should be able to support them without too much trouble.

### Additional contract requirements

- `World::reserve<T: Bundle>(&mut self, additional: u32)` panics when the component set described by `T` contains the same component type more than once. In debug builds the panic message includes the name of the duplicated component type; in release builds it contains a generic duplicate-component message.
- `World::spawn` panics in the same way when given a bundle whose component set contains a duplicate component type.
