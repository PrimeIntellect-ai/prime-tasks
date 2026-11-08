Import aliases (crates) in doc comment injection retain their unresolvedReference
```rs
/// ```
/// use thing as Unresolved;
/// extern crate Krate;
/// ```
struct S;
```

here `Unresolved` is tagged `unresolvedReference` (and `Krate` too), even though we strip this tag usually. Probably not hjere as these two identifiers are considered names (and usually names do not turn `unresolvedReference`!)

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->

<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":null}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->

### Additional contract requirements

In injected Rust code within documentation comments, identifiers declared by `extern crate` and identifiers introduced as aliases in `use ... as ...` imports must not be highlighted as `unresolvedReference`.
