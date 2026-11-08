Include public/private dependency status in `cargo metadata`
### Problem

related to https://github.com/rust-lang/rust/issues/44663

Information about whether or not a dependency is public is not included in the output of `cargo metadata`.

This could be useful for custom subcommands. `cargo override`, would find this useful for https://github.com/eopb/cargo-override/issues/121

### Proposed Solution

When `-Zpublic-dependency` is enabled, include a boolean flag in `cargo metadata`s output at `packages[].dependencies[].public`.
If  `-Zpublic-dependency` is not enabled,  this flag should not appear in `cargo metadata` output.

### Notes

If this feature request is accepted, I'm happy to claim and take a crack at working on it

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->

<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"eopb"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->
