Align FFI API with arrow's C++ API
Generally, the FFI should support the possibility of an external consumer to allocate the bridge structs (`ArrowArray` and `ArrowSchema`).

This requires that the bridge struct is not allocated by us; we should instead expect an allocated and aligned pointer that we can write the struct to it. Such change is backward-incompatible.

### Additional contract requirements

The `arrow2::ffi` module must expose the following public items:

- `Ffi_ArrowArray`, a public struct, with an associated function `Ffi_ArrowArray::empty() -> Ffi_ArrowArray`.
- `Ffi_ArrowSchema`, a public struct, with an associated function `Ffi_ArrowSchema::empty() -> Ffi_ArrowSchema`.
- `pub unsafe fn export_array_to_c(array: Arc<dyn Array>, ptr: *mut Ffi_ArrowArray)`.
- `pub unsafe fn export_field_to_c(field: &Field, ptr: *mut Ffi_ArrowSchema)`.
- `pub fn import_field_from_c(field: &Ffi_ArrowSchema) -> Result<Field>`.
- `pub fn import_array_from_c(array: Box<Ffi_ArrowArray>, field: &Field) -> Result<Box<dyn Array>>`.

`Array` is `arrow2::array::Array`, `Field` is `arrow2::datatypes::Field`, and `Result` is `arrow2::error::Result`.
