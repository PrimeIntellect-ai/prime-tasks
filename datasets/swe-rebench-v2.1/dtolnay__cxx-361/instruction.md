Allow UniquePtr::new on Trivial ExternTypes
Example from autocxx:

```rust
mod ffi {
    unsafe impl cxx::ExternType for bindgen::A {
        type Id = cxx::type_id!("A");
        type Kind = cxx::kind::Trivial;
    }
    mod bindgen {
        #[repr(C)]
        pub struct A {
            pub a: u32,
        }
    }
    #[cxx::bridge]
    pub mod cxxbridge {
        impl UniquePtr<A> {}
        extern "C" {
            include!("input.h");
            type A = super::bindgen::A;
        }
    }
}

fn main() {
    let a = ffi::cxxbridge::A { a: 14 };
    let _ = cxx::UniquePtr::new(a);
}
```

fails because it hits this `unreachable!`:

```rust
// Methods are private; not intended to be implemented outside of cxxbridge
// codebase.
pub unsafe trait UniquePtrTarget {
   //...
    #[doc(hidden)]
    [HIDDEN]
    where
        Self: Sized,
    {
        // Opaque C types do not get this method because they can never exist by
        // value on the Rust side of the bridge.
        let _ = value;
        unreachable!()
    }
    //...
}
```

[HIDDEN]

### Additional contract requirements

- `UniquePtr::new` must be usable with values of trivial extern types, producing an owning `UniquePtr`.
- An opaque extern type must not be constructible by value through `UniquePtr::new`; attempting to do so must fail to compile.
