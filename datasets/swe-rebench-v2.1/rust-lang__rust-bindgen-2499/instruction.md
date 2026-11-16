Mishandle of variadic function with wrapped static functions
<!-- Thanks for filing a bindgen issue! We appreciate it :-) -->

### Input C/C++ Header

```C++
static inline void foo(int flags, ...) {
    // ...
}
```

### Bindgen Invocation

```
$ bindgen --experimental --wrap-static-fns input.h
```

### Actual Results

```rust
extern "C" {
    #[link_name = "foo__extern"]
    pub fn foo(flags: ::std::os::raw::c_int, ...);
}
```

and

```c
#include "input.h"

// Static wrappers

void foo__extern(int flags) { foo(flags); } // At least missing `...`
```

### Expected Results

I expect bindgen to either handle correctly (what ever that would be) or to ignore those bind of functions.

cc @pvdrz
