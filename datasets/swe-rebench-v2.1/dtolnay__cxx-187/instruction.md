Extern C-like enums
The enum support from #170 doesn't apply to interop with existing enums for which C++ is the source of truth.

I wonder if we could handle this use case as follows:

```rust
mod ffi {
    enum SmallPrime {
        Two = 2,
        Three = 3,
        Five = 5,
    }

    extern "C" {
        type SmallPrime;
    }
}
```

where we ask that the enum variants be provided just like in #170, but if the same type name is also an extern "C" type then we don't emit a C++ enum class definition, but instead emit static assertions on the C++ side asserting that the cxx bridge discriminants are all the same as the existing C++ enum's values.
