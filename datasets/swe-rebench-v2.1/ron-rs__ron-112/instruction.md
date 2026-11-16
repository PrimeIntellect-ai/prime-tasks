Support for multi-line string literals
Will RON ever support multi-line string literals? This is a feature that missing from JSON, but is present in YAML, TOML, and in Rust proper, like so:

```yaml
# YAML multi-line string literals
key: >
  This is a very long sentence
  that spans several lines in the YAML
  but which will be rendered as a string
  without carriage returns.
```

```toml
# TOML multi-line string literals
key = '''
    This is a very long sentence
    that spans several lines in the TOML
    but which will be rendered as a string
    without carriage returns.
'''
```

```rust
// Rust multi-line string literals
let key = r#"
    This is a very long sentence
    that spans several lines in Rust
    but which will be rendered as a string
    without carriage returns.
"#;

let key = r##"
    This is a sentence which happens
    to contain a '#' character inside.
"##;
```

This could be a useful for storing localized strings for dialogue boxes, for example, or other complex strings that are too tedious and error-prone to escape by hand. Here is some pseudo-RON syntax showing how this feature could be used:

```ron
System(
    arch: "x86_64-linux",
    shell: "/usr/bin/bash",
    packages: ["firefox", "git", "rustup"],
    startup: r##"
        #!/usr/bin/bash
        export PS1="..."
        echo "Done booting!"
    "##,
)
```

Given that RON already mimics Rust's notation quite well, adopting its syntax for raw string literals would make this feature feel right at home. See the [official reference page](https://doc.rust-lang.org/reference/tokens.html#raw-string-literals) and [Rust By Example](https://rustbyexample.com/std/str.html#literals-and-escapes) for details.
