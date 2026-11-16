[Bug] Panic on truncating non-ASCII content
### Describe the bug

comfy-table panics when rendering a dynamically-arranged non-ASCII content in a narrow cell.

### Steps to reproduce

Complete setup: https://gitlab.com/uasi/20250117-comfy-table-panic

```rs
// Rust 1.84.0, comfy-table 7.1.3

fn main() {
    let mut table = comfy_table::Table::new();
    table
        .set_header(vec!["Header1"])
        .set_width(20)
        .add_row(vec!["あいうえおかきくけこさしすせそたちつてと"])
        .set_content_arrangement(comfy_table::ContentArrangement::Dynamic);

    for row in table.row_iter_mut() {
        row.max_height(1); // 2 -> also panics, 3 -> ok
    }

    println!("{table}");
}
```

### Logs (if applicable)

```
% RUST_BACKTRACE=1 cargo run
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.20s
     Running `target/debug/comfy-table-panic`
thread 'main' panicked at /Users/uasi/.rustup/toolchains/stable-aarch64-apple-darwin/lib/rustlib/src/rust/library/alloc/src/string.rs:1472:13:
assertion failed: self.is_char_boundary(new_len)
stack backtrace:
   0: rust_begin_unwind
             at /rustc/9fc6b43126469e3858e2fe86cafb4f0fd5068869/library/std/src/panicking.rs:665:5
   1: core::panicking::panic_fmt
             at /rustc/9fc6b43126469e3858e2fe86cafb4f0fd5068869/library/core/src/panicking.rs:76:14
   2: core::panicking::panic
             at /rustc/9fc6b43126469e3858e2fe86cafb4f0fd5068869/library/core/src/panicking.rs:148:5
   3: alloc::string::String::truncate
             at /Users/uasi/.rustup/toolchains/stable-aarch64-apple-darwin/lib/rustlib/src/rust/library/alloc/src/string.rs:1472:13
   4: comfy_table::utils::formatting::content_format::format_row
             at /Users/uasi/.cargo/registry/src/index.crates.io-6f17d22bba15001f/comfy-table-7.1.3/src/utils/formatting/content_format.rs:126:25
   5: comfy_table::utils::formatting::content_format::format_content
             at /Users/uasi/.cargo/registry/src/index.crates.io-6f17d22bba15001f/comfy-table-7.1.3/src/utils/formatting/content_format.rs:55:28
   6: comfy_table::utils::build_table
             at /Users/uasi/.cargo/registry/src/index.crates.io-6f17d22bba15001f/comfy-table-7.1.3/src/utils/mod.rs:52:19
   7: comfy_table::table::Table::lines
             at /Users/uasi/.cargo/registry/src/index.crates.io-6f17d22bba15001f/comfy-table-7.1.3/src/table.rs:95:9
   8: <comfy_table::table::Table as core::fmt::Display>::fmt
             at /Users/uasi/.cargo/registry/src/index.crates.io-6f17d22bba15001f/comfy-table-7.1.3/src/table.rs:47:25
   9: core::fmt::rt::Argument::fmt
             at /rustc/9fc6b43126469e3858e2fe86cafb4f0fd5068869/library/core/src/fmt/rt.rs:177:76
  10: core::fmt::write
             at /rustc/9fc6b43126469e3858e2fe86cafb4f0fd5068869/library/core/src/fmt/mod.rs:1189:21
  11: std::io::Write::write_fmt
             at /rustc/9fc6b43126469e3858e2fe86cafb4f0fd5068869/library/std/src/io/mod.rs:1884:15
  12: <&std::io::stdio::Stdout as std::io::Write>::write_fmt
             at /rustc/9fc6b43126469e3858e2fe86cafb4f0fd5068869/library/std/src/io/stdio.rs:792:9
  13: <std::io::stdio::Stdout as std::io::Write>::write_fmt
             at /rustc/9fc6b43126469e3858e2fe86cafb4f0fd5068869/library/std/src/io/stdio.rs:766:9
  14: std::io::stdio::print_to
             at /rustc/9fc6b43126469e3858e2fe86cafb4f0fd5068869/library/std/src/io/stdio.rs:1122:21
  15: std::io::stdio::_print
             at /rustc/9fc6b43126469e3858e2fe86cafb4f0fd5068869/library/std/src/io/stdio.rs:1232:5
  16: comfy_table_panic::main
             at ./src/main.rs:15:5
  17: core::ops::function::FnOnce::call_once
             at /Users/uasi/.rustup/toolchains/stable-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/ops/function.rs:250:5
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
```

### Operating system

macOS 15.2

### Comfy-table version

v7.1.3

### Additional context

Related issue https://github.com/Nukesor/comfy-table/issues/53

himalaya is affected by this bug https://github.com/pimalaya/himalaya/issues/497

### Additional contract requirements

- For a dynamically arranged table with a `Header1` header, width 20, and the Japanese row content shown in the reproduction, rendering must not panic when the row’s maximum height is 1 or 2. Any truncation must preserve valid Unicode text and use the default `...` truncation indicator when content is omitted.
- Rendering must also not panic for dynamically arranged content containing repeated composite Unicode emoji in a width-15 table with a `Header1` header and a row maximum height of 1. Truncation must preserve valid Unicode text and respect the configured table width.
