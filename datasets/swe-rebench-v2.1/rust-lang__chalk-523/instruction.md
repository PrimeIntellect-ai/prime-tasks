Add callback to get repr data
To perform some of wf checks, we need to know whether or not struct has `#[repr(C)]` or `#[repr(packed)]` (only those two). So we need to add a database callback to get that info given an adt id and extend the parser to account for it in ChalkDatabase.

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->
This issue has been assigned to @voidc via [this comment](https://github.com/rust-lang/chalk/issues/517#issuecomment-643694192).
<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"voidc"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->

### Additional contract requirements

The database query is named `RustIrDatabase::adt_repr` and returns an `AdtRepr` with `repr_c` and `repr_packed` fields. For a parsed struct, querying its representation with that struct's ADT id must report independently whether `repr(C)` and `repr(packed)` are present. Structs with neither attribute report both fields as `false`.
