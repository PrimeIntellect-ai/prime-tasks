`NOBITS` with `sh_offset==0` causes `build::elf::Builder::write` error
Hello. AFAIK `sh_offset` field is completely meaningless in case of `SHT_NOBITS` section. Sometimes it is equal to `0`: I encountered such a binary "in the wild". In this case, however, you cannot `write` the (valid) binary parsed by the ELF builder: it throws an error.

Probably the simplest  possible solution would be to [HIDDEN]

```rust
if section.sh_offset < writer.reserved_len() as u64 { ... }
```

```rust
// The input sh_offset needs to be preserved so that offsets in program
// headers are correct.
writer.reserve_until(section.sh_offset as usize);
```

```rust
if out_section.offset as u64 != section.sh_offset {...}
```

Let me know what do you think.

### Additional contract requirements

- `build::elf::Builder::write` must succeed for a valid ELF input containing an `SHT_NOBITS` section whose `sh_offset` is zero.
