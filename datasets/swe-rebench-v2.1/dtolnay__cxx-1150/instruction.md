`#[cxx_name = "type"]` yields an error "expected identifier"
I have a struct in C++ with a field named **type**:

```cpp
struct X {
    int32 type;
}
```

Then I represent it in Rust as a shared type inside of the `#[cxx::bridge]` mod:

```rust
struct X {
    #[cxx_name = "type"]
    x_type: i32,
}
```

But this yields an error:
```
 error[cxxbridge]: expected identifier
      ┌─ src/lib.rs:138:22
      │
  138 │         #[cxx_name = "type"]
      │                      ^^^^^^ expected identifier
```

At the same time other values for `cxx_name` such as `type1` work fine.
