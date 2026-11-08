Modules inserted via `include` can't resolve later files
**rust-analyzer version**: 0.4.2042-standalone (b333f85a9 2024-07-19)

**rustc version**: rustc 1.78.0 (9b00956e5 2024-04-29)

**editor or extension**: VS Code

A test case to reproduce based on `nested_include`
```rust
#[test]
fn include_with_mod_path() {
    check(
        r#"
//- minicore: include
//- /lib.rs
include!("out_dir/includes.rs");

//- /out_dir/includes.rs
#[path = "."]
pub mod company_name {
    pub mod network {
        pub mod v1;
    }
}
//- /out_dir/network/v1.rs
pub struct IpAddress {
    pub ip_type: &'static str,
}
/// Nested message and enum types in `IpAddress`.
pub mod ip_address {
    pub enum IpType {
        IpV4(u32),
    }
}

"#,
        expect![[r#"
            [HIDDEN]
        "#]],
    );
}
```
The types in the `v1` module don't resolve, failing the test. Rust has no problem handling modules with `#[path = "."]`. RA also can handle modules with `#[path = "."]` if they aren't `include!`d, so this seems to be a problem exclusive to `include!`.

### Additional contract requirements

- Resolve out-of-line modules declared in Rust source supplied through `include!` to their corresponding source files, including when the module uses `#[path = "."]`. Items declared in those files should resolve through the resulting module tree.
