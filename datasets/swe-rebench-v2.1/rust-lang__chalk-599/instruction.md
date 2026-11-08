Refactor `FnPointer` and `FnDef` to share function signature logic
Right now we have a lot of code duplication in handling the ABI, safety, variadic-ness, and other information for function pointers and function definitions. We should encapsulate this in something like a `FnSig` struct, and use that in both `FnPointer` and `FnDef`.

### Additional contract requirements

- `chalk_ir::FnSig<I>` is a public struct with public fields `abi: I::FnAbi`, `safety: Safety`, and `variadic: bool`.
- `chalk_ir::FnSig<I>` implements `Copy`, `Clone`, `PartialEq`, `Eq`, `Hash`, and `Debug`.
- `chalk_ir::FnPointer<I>` exposes the function signature through a public field `sig: FnSig<I>` instead of separate `abi`, `safety`, and `variadic` fields.
- `chalk_solve::rust_ir::FnDefDatum<I>` exposes the function signature through a public field `sig: FnSig<I>` instead of separate `abi`, `safety`, and `variadic` fields.
