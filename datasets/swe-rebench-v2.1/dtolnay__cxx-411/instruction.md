Nested structs lead to incomplete type error
If I put this in my `mod ffi`:

    struct A {
        b: B,
    }
    struct B {
        c: i32,
    }

I get this error during compilation:

```
warning: /.../lib.rs.cc:255:5: error: field has incomplete type 'org::example::B'
warning:   B b;
warning:     ^
warning: /.../lib.rs.cc:225:8: note: forward declaration of 'org::example::B'
warning: struct B;
warning:        ^
warning: 1 error generated.
```

If I change it to `b: Box<B>` it works fine.
