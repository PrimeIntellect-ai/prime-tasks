MSL struct initialization fails on array types
> program_source:1114:90: error: cannot initialize an array element of type 'type1' (aka 'float') with an lvalue of type 'type29' (aka 'type1 [1]')

Code:
```rust
    typedef type1 type29[const_1u1];
    typedef thread type29 *type30;
    typedef thread type1 *type31;
    typedef metal::bool3 type32;
    struct type33 {
        type2 member14;
        type2 member15;
        type2 member16;
        type3 member17;
        type2 member18;
        type2 member19;
        type29 member20;
    };
...
type29 global15 = {};
const auto _tmp = type33 {global9, global10, global11, global12, global13, global14, global15};
```

### Additional contract requirements

When the MSL backend emits a struct initializer whose member has an array type, the generated MSL must initialize that member validly; it must not use the whole array value where an individual array element is required.
