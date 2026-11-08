Tracking issue for RFC 45: Move `hdl.Memory` to `lib.Memory`
- RFC PR: https://github.com/amaranth-lang/rfcs/pull/45
- Implementation PR: https://github.com/amaranth-lang/amaranth/pull/1142
- Documentation PR: https://github.com/amaranth-lang/amaranth/pull/1228
- Removal PR: https://github.com/amaranth-lang/amaranth/pull/1395

### Additional contract requirements

- `amaranth.hdl.Memory` must be removed: the name `Memory` must no longer be an attribute of the
  `amaranth.hdl` module, and must not be importable from it. The replacement is
  `amaranth.lib.memory.Memory`.
