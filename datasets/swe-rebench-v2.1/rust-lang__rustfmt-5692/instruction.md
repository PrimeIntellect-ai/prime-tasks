duplicating `where` clauses that contains (unused) braces
This affects very specialized and a few months outdated codebases that
- had to use `#[allow(unused_braces)]` (before it was recently lifted) to invoke macros from `where` clauses, and
- there is an asterisk-based or two slash-based comment in the `struct` or `enum` definition.

Hence likely to be a lower priority. But I'm reporting this in case it's connected to any other/potential bigger issues.

Run `cargo fmt` from recent `nightly` (noticed with `nightly` as of Feb 2, 2023, chances are the problem existed before; the bug still exists as of Feb 15, 2023) on a project with `lib.rs` containing the following (which does compile; or get the code from https://github.com/peter-kehl/fmt_bug_where_braces):
```rust
#![allow(incomplete_features)]
#![feature(generic_const_exprs)]

macro_rules! num_slots {
    ($c:expr) => {
        1
    };
}

#[allow(dead_code)]
#[allow(unused_braces)]
struct S<const C: usize>
where
    [(); { num_slots!(C) }]:, {
    /* An asterisk-based, or a double-slash-prefixed, comment here is
       required to trigger the fmt bug.

    A single-line triple-slash-prefixed comment (with a field following it) is not enough - it will not trigger the fmt bug.

    Side note: If you have a combination of two, or all three of the
    above mentioned types of comments here, some of them disappear
    after `cargo fmt`.

    The bug gets triggered even if a field definition following the
    (asterisk-based, or a double-slash-prefixed) comment, too.
    */
}
```

That injects an extra line `num_slots!(C) }]:, {`, which makes the project not compile anymore:

```rust
cargo fmt
git diff
diff --git a/src/lib.rs b/src/lib.rs
index ce30fe0..44f77eb 100644
--- a/src/lib.rs
+++ b/src/lib.rs
@@ -12,6 +12,7 @@ macro_rules! num_slots {
 struct S<const C: usize>
 where
     [(); { num_slots!(C) }]:, {
+    num_slots!(C) }]:, {
     /* An asterisk-based, or a double-slash-prefixed, comment here is
        required to trigger the fmt bug.
```

(Initially reported as https://github.com/rust-lang/rust/issues/107610. The source that triggered the bug is not a part of rust-lang/rust itself, but it's from my experimentation.)

### Additional contract requirements

Formatting the reported item must not duplicate any `where`-clause text into its body or produce invalid formatted Rust. Comments in the item body must be preserved when block, line, and doc comments occur together, including when a field follows them.
