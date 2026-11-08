Add `Mat4::ortho`
Because orthographic projections are cool.  If you want this, I'll happily PR it.

### Additional contract requirements

- The public method is named `Mat4::orthographic_rh`; the `ortho` in the title refers to this method. Its signature is `pub fn orthographic_rh(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) -> Mat4`.
- The returned matrix maps a homogeneous point `(x, y, z, 1)` to `(x', y', z', 1)` where:
  - `x' = 2 * x / (right - left) - (right + left) / (right - left)`
  - `y' = 2 * y / (top - bottom) - (top + bottom) / (top - bottom)`
  - `z' = -2 * z / (far - near) - (far + near) / (far - near)`
- For the bounds `left = -10`, `right = 10`, `bottom = -5`, `top = 5`, `near = 0`, `far = -10`, the point `(5, 5, -5, 1)` maps to `(0.5, 1.0, -2.0, 1.0)`.
- If any pair of bounds are equal, the resulting matrix contains infinities; the function performs no runtime validation and does not panic.
