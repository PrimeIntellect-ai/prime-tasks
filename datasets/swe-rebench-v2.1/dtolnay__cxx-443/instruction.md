Bug when defining methods on shared structs
```rust
// str_test.rs
#[cxx::bridge]
mod ffi {
    struct A {
        a: f32,
    }

    extern "Rust"{
        fn hello(self: &A) -> String;
    }
}
```

Then run
```bash
cxxbridge str_test.rs
```

We get:
```cpp
...

::rust::String A::hello() const noexcept {
  ::rust::MaybeUninit<::rust::String> return$;
  cxxbridge05$A$hello(*this&return$.value);
  return ::std::move(return$.value);
}
```

Note that there's a missing "," in hello invocation.
It should be `cxxbridge05$A$hello(*this, &return$.value);` instead of `cxxbridge05$A$hello(*this&return$.value);`


<!--  ❤️  -->
