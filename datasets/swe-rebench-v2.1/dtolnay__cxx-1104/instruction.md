[Feature Request] Support Vec<bool>
Can we please add support for Vec<bool>? There shouldn't be any special magic required, and though #169 claims to have fixed it, the snippet below doesn't work in any post-`1.0.0` version of `cxx` I tried.

```
#[cxx::bridge]
mod ffi {
    unsafe extern "C++" {
        fn gimme_vecbool() -> Vec<bool>;
    }
}
```

Currently, the only workaround I know about is wrapping the `bool` in a structure, which works but is annoying to work with.
