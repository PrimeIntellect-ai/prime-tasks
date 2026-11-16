Order sensitivity across namespaces
The namespace sorting introduced in #370 does not handle alphabetically lesser namespaces referencing items from alphabetically greater namespaces.

```rust
#[cxx::bridge]
mod ffi {
    #[namespace = "first"]
    struct First {
        second: Box<Second>,
    }

    #[namespace = "second"]
    struct Second {
        i: i32,
    }
}
```

```console
target/debug/build/demo-d74fe843f72e57b6/out/cxxbridge/sources/demo/src/main.rs.cc:154:17: error: ‘::second’ has not been declared
  154 |   ::rust::Box<::second::Second> second;
      |                 ^~~~~~
target/debug/build/demo-d74fe843f72e57b6/out/cxxbridge/sources/demo/src/main.rs.cc:154:31: error: template argument 1 is invalid
  154 |   ::rust::Box<::second::Second> second;
      |                               ^
```
