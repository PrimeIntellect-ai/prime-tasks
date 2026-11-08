model `ObjectSafe` goals
We need to model object safety. I think a decent starting point is:

* add a `ObjectSafe(TraitId)` domain goal
* add a `RustIrDatabase` callback `is_object_safe(TraitId)`
* [HIDDEN]
* in rustc-integration, add a `#[object_safe]` flag attached to traits, and use that to test

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->
This issue has been assigned to @Mcat12 via [this comment](https://github.com/rust-lang/chalk/issues/434#issuecomment-625874455).
<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"Mcat12"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->

### Additional contract requirements

- The `RustIrDatabase` callback `is_object_safe` takes a `TraitId` and returns a `bool` that is `true` exactly when the trait is object safe.
- The object-safety goal is written as `ObjectSafe(Foo)`, where `Foo` is the name of a trait. The goal is provable exactly when `is_object_safe` returns `true` for that trait.
- In the integration used for object-safety queries, `#[object_safe]` marks a trait as object safe, and a trait without that flag is not object safe.
- For the invalid-input parser case that encounters `i32` at offsets 8-11, report exactly: `parse error: UnrecognizedToken { token: (8, Token(53, "i32"), 11), expected: ["r#\"([A-Za-z]|_)([A-Za-z0-9]|_)*\"#"] }`.

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->
This issue has been assigned to @Mcat12 via [this comment](https://github.com/rust-lang/chalk/issues/434#issuecomment-625874455).
<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"Mcat12"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->
