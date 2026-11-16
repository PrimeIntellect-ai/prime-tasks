Why no {distance,length}_squared for {I,U}Vec{2,3,4} ?
I see no reason for the integer vectors to not have the `distance_squared` and `length_squared` methods, like the rest of the numeric vectors have. Is there any?

### Additional contract requirements

- `length_squared(self)` is provided for `IVec2`, `IVec3`, `IVec4`, `I64Vec2`, `I64Vec3`, `I64Vec4`, `UVec2`, `UVec3`, `UVec4`, `U64Vec2`, `U64Vec3` and `U64Vec4`. It returns the sum of the squares of the components, using the same integer type as the vector's components: `i32` for `IVec2`/`IVec3`/`IVec4`, `i64` for `I64Vec2`/`I64Vec3`/`I64Vec4`, `u32` for `UVec2`/`UVec3`/`UVec4`, and `u64` for `U64Vec2`/`U64Vec3`/`U64Vec4`.
- `distance_squared(self, rhs)` is provided for the signed integer vector types `IVec2`, `IVec3`, `IVec4`, `I64Vec2`, `I64Vec3` and `I64Vec4`. It takes another vector of the same type and returns the squared length of the difference `self - rhs`, using the same integer type as the vector's components.
